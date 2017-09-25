package main

import (
	"fmt"
	"io/ioutil"
	"net/url"
	"os/exec"
	"time"

	"gopkg.in/gorilla/websocket.v1"
)

type MailerOptions struct {
	Server      string
	Port        int
	Recipient   string
	DialTimeout int
}

type MailerState struct {
	opts       MailerOptions
	url        string
	ws         *websocket.Conn
	messages   chan string
	readerDone chan error
}

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

func (s *MailerState) Close() {
	defer s.ws.Close()
	err := s.ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	if err != nil {
		logError("writing websocket close failed: %s", err)
	}
}

func (s *MailerState) SendMail(text string) {
	logInfo("forking sendmail process")
	logInfo("sending message: %s", text)
	body := fmt.Sprintf("%s\n\nSENT %s", text, time.Now().Format(time.RFC3339))
	from := s.opts.Recipient
	to := s.opts.Recipient
	header := fmt.Sprintf("Subject: Beetle system notification\nFrom: %s\nTo: %s\n\n", from, to)
	sendmail := exec.Command("/usr/sbin/sendmail", "-i", "-f", from, to)
	stdin, err := sendmail.StdinPipe()
	if err != nil {
		logError("could not obtain stdin pipe from sendmail: %v", err)
		return
	}
	stdout, err := sendmail.StdoutPipe()
	if err != nil {
		logError("could not obtain stdout pipe from sendmail: %v", err)
		return
	}
	sendmail.Start()
	stdin.Write([]byte(header))
	stdin.Write([]byte(body))
	stdin.Close()
	sendmailOutput, err := ioutil.ReadAll(stdout)
	if err != nil {
		logError("could not read sendmail output: %v", err)
	} else if len(sendmailOutput) > 0 {
		logInfo("sendmail command output: %s", string(sendmailOutput))
	}
	sendmail.Wait()
	logInfo("sendmail finished!")
}

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
			// Run sendmail in a separate goroutine, because it can
			// take a while and we don't want to miss
			// notifications. And we want to ext cleanly and quickly.
			go s.SendMail(msg)
		case err := <-s.readerDone:
			// If the reader has terminated, so should we.
			return err
		case <-ticker.C:
			// Give outer loop a chance to detect interrupts.
		}
	}
	return nil
}

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
