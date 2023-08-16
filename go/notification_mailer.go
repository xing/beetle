package main

import (
	"fmt"
	"net/smtp"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/xing/beetle/consul"
)

// MailerSettings contain a server address for a listening websocket and a
// recipient address for notification emails, as well as a timeout interval for
// websocket connections.
type MailerSettings struct {
	Server      string
	Port        int
	DialTimeout int
	Sender      string
	Recipients  []string
	MailRelay   string
}

// MailerOptions contain pointers to the initial config and potentially a Consul
// client.
type MailerOptions struct {
	Config       *Config
	ConsulClient *consul.Client
}

// MailerState contains mailer options and state variables.
type MailerState struct {
	opts          *MailerOptions
	mutex         sync.Mutex
	url           string
	ws            *websocket.Conn
	messages      chan string
	readerDone    chan error
	configChanges chan consul.Env
}

// GetConfig returns the client configuration in a thread safe way.
func (s *MailerState) GetConfig() *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.opts.Config
}

// SetConfig sets replaces the current config with a new one in athread safe way
// and returns the old config.
func (s *MailerState) SetConfig(config *Config) *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	oldconfig := s.opts.Config
	s.opts.Config = config
	return oldconfig
}

// MailerSettings returns the current mailer settings.
func (opts *MailerOptions) GetMailerSettings() *MailerSettings {
	return &MailerSettings{
		Server:      opts.Config.Server,
		Port:        opts.Config.Port,
		DialTimeout: opts.Config.DialTimeout,
		Sender:      opts.Config.MailFrom,
		Recipients:  strings.Split(opts.Config.MailTo, ","),
		MailRelay:   opts.Config.MailRelay,
	}
}

// Connect connects to a websocket for reading notifcation messages.
func (s *MailerState) Connect() (err error) {
	// copy default dialer to avoid race conditions
	dialer := *websocket.DefaultDialer
	dialer.HandshakeTimeout = time.Duration(s.opts.Config.DialTimeout) * time.Second
	logInfo("connecting to %s, timeout: %s", s.url, dialer.HandshakeTimeout)
	s.ws, _, err = dialer.Dial(s.url, nil)
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
	settings := opts.GetMailerSettings()
	logInfo("sending message: %s using %v", text, settings)
	to := strings.Join(settings.Recipients, ",")
	from := settings.Sender
	subject := "Beetle system notification"
	body := text + "\n\n" + "SENT: " + time.Now().Format(time.RFC3339)
	msg := fmt.Sprintf("To: %s\r\nSubject: %s\r\n\r\n%s\r\n", to, subject, body)
	err := smtp.SendMail(settings.MailRelay, nil, from, settings.Recipients, []byte(msg))
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
	var err error
	if s.opts.ConsulClient != nil {
		s.configChanges, err = s.opts.ConsulClient.WatchConfig()
		if err != nil {
			return err
		}
	} else {
		s.configChanges = make(chan consul.Env)
	}
	err = s.Connect()
	if err != nil {
		return err
	}
	defer s.Close()
	go s.Reader()
	ticker := time.NewTicker(1 * time.Second)
	tick := 0
	for !interrupted {
		select {
		case msg := <-s.messages:
			if msg == "HEARTBEAT" {
				logInfo("received HEARTBEAT from configuration server")
				continue
			}
			SendMail(msg, *s.opts)
		case err := <-s.readerDone:
			// If the reader has terminated, so should we.
			return err
		case <-ticker.C:
			// Give outer loop a chance to detect interrupts.
			tick++
			// Send heartbeat to config server.
			interval := s.GetConfig().ClientHeartbeat
			if tick%interval == 0 {
				err := s.ws.WriteMessage(websocket.TextMessage, []byte("HEARTBEAT"))
				if err != nil {
					logError("sending HEARTBEAT to configuration server failed: %s", err)
					return err
				}
			}
		case env := <-s.configChanges:
			if env != nil {
				newconfig := buildConfig(env)
				s.SetConfig(newconfig)
				logInfo("updated server config from consul: %s", s.GetConfig())
			}
		}
	}
	return nil
}

// RunNotificationMailer runs a mailer, supervises and restarts it when it
// exits, until a TERM signal has been received.
func RunNotificationMailer(o MailerOptions) error {
	logInfo("notification mailer started with options: %+v\n", o)
	for !interrupted {
		addr := fmt.Sprintf("%s:%d", o.Config.Server, o.Config.Port)
		u := url.URL{Scheme: "ws", Host: addr, Path: "/notifications"}
		state := &MailerState{opts: &o, url: u.String(), messages: make(chan string, 100), readerDone: make(chan error, 1)}
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
