package main

import (
	"fmt"
	"net/smtp"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// MailerOptions contain a server address for a listening websocket and a
// recipient address for notification emails, as well as timeout interval for
// websocket connections.
type MailerOptions struct {
	Server      string
	Port        int
	DialTimeout int
	Sender      string
	Recipients  []string
	MailRelay   string
}

// MailerState contains mailer options and state variables.
type MailerState struct {
	opts       MailerOptions
	url        string
	ws         *websocket.Conn
	messages   chan string
	readerDone chan error
}

// Connect connects to a websocket for reading notifcation messages.
func (s *MailerState) Connect() (err error) {
	logInfo("connecting to %s", s.url)
	websocket.DefaultDialer.HandshakeTimeout = time.Duration(s.opts.DialTimeout) * time.Second
	s.ws, _, err = websocket.DefaultDialer.Dial(s.url, nil)
	if err != nil {
		return
	}
	logInfo("established web socket connection")
	return
}

// Close sends a Close message on the websocket and closes it.
func (s *MailerState) Close() {
	defer s.ws.Close()
	err := s.ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	if err != nil {
		logError("writing websocket close failed: %s", err)
	}
}

// SendMail sends a notification mail with a given text as body. It
// uses the net/smtp.
func SendMail(text string, opts MailerOptions) error {
	logInfo("sending message: %s using %v", text, opts)
	to := strings.Join(opts.Recipients, ",")
	from := opts.Sender
	subject := "Beetle system notification"
	body := text + "\n\n" + "SENT: " + time.Now().Format(time.RFC3339)
	msg := fmt.Sprintf("To: %s\r\nSubject: %s\r\n\r\n%s\r\n", to, subject, body)
	err := smtp.SendMail(opts.MailRelay, nil, from, opts.Recipients, []byte(msg))
	if err != nil {
		logError("failed to send mail: %s", err)
		return err
	}
	logInfo("sent notification mail!")
	return nil
}

// Reader reads notification messages from a websocket and forwards them on an
// internal channel.
func (s *MailerState) Reader() {
	for !interrupted {
		logDebug("reading message")
		msgType, bytes, err := s.ws.ReadMessage()
		if err != nil || msgType != websocket.TextMessage {
			logError("error reading from server socket: %s", err)
			s.readerDone <- err
			return
		}
		str := string(bytes)
		logDebug("received: %s", str)
		s.messages <- str
	}
	close(s.readerDone)
}

// RunMailer starts a reader which listens on a websocket for notification
// messages and sends notification emails. It exits when a TERM signal has been
// received or wthe the reader as terminated.
func (s *MailerState) RunMailer() error {
	err := s.Connect()
	if err != nil {
		return err
	}
	defer s.Close()
	go s.Reader()
	ticker := time.NewTicker(1 * time.Second)
	for !interrupted {
		select {
		case msg := <-s.messages:
			// Run sendmail in a separate goroutine, because it can take a while
			// and we don't want to miss notifications. And we want to ext
			// cleanly and quickly.
			go SendMail(msg, s.opts)
		case err := <-s.readerDone:
			// If the reader has terminated, so should we.
			return err
		case <-ticker.C:
			// Give outer loop a chance to detect interrupts.
		}
	}
	return nil
}

// RunNotificationMailer runs a mailer, supervises and restarts it when it
// exits, until a TERM signal has been received.
func RunNotificationMailer(o MailerOptions) error {
	logInfo("notification mailer started with options: %+v\n", o)
	for !interrupted {
		addr := fmt.Sprintf("%s:%d", o.Server, o.Port)
		u := url.URL{Scheme: "ws", Host: addr, Path: "/notifications"}
		state := &MailerState{opts: o, url: u.String(), messages: make(chan string, 100), readerDone: make(chan error, 1)}
		err := state.RunMailer()
		if err != nil {
			logError("%s", err)
			if !interrupted {
				time.Sleep(1 * time.Second)
			}
		}

	}
	logInfo("notification mailer terminated")
	return nil
}
