package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

type ClientOptions struct {
	Server            string
	Port              int
	Id                string
	ConfigFile        string
	RedisMasterFile   string
	HeartbeatInterval int
}

type ClientState struct {
	opts          ClientOptions
	url           string
	ws            *websocket.Conn
	input         chan MsgContent
	currentMaster *RedisShim
	currentToken  string
	writerDone    chan struct{}
	readerDone    chan struct{}
}

func (s *ClientState) Connect() (err error) {
	logInfo("connecting to %s", s.url)
	s.ws, _, err = websocket.DefaultDialer.Dial(s.url, nil)
	if err != nil {
		return
	}
	logInfo("established web socket connection")
	return
}

func (s *ClientState) Close() {
	defer s.ws.Close()
	err := s.ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	if err != nil {
		logError("writing websocket close failed: %s", err)
	}
}

func (s *ClientState) send(msg MsgContent) error {
	b, err := json.Marshal(msg)
	if err != nil {
		logError("could not marshal message: %s", err)
		return err
	}
	err = s.ws.WriteMessage(websocket.TextMessage, b)
	if err != nil {
		logError("could not send message: %s", err)
		return err
	}
	logDebug("sent:     %s", string(b))
	return nil
}

func (s *ClientState) SendHeartBeat() error {
	return s.send(MsgContent{Name: HEARTBEAT, Id: s.opts.Id})
}

func (s *ClientState) Ping(pingMsg MsgContent) error {
	logInfo("Received ping message")
	if s.RedeemToken(pingMsg.Token) {
		return s.SendPong()
	}
	return nil
}

func (s *ClientState) RedeemToken(token string) bool {
	if s.currentToken == "" || token > s.currentToken {
		s.currentToken = token
	}
	tokenValid := token >= s.currentToken
	if !tokenValid {
		logInfo("invalid token: %s is not greater or equal to %s", token, s.currentToken)
	}
	return tokenValid
}

func (s *ClientState) SendPong() error {
	return s.send(MsgContent{Name: PONG, Id: s.opts.Id, Token: s.currentToken})
}

func (s *ClientState) SendClientInvalidated() error {
	return s.send(MsgContent{Name: CLIENT_INVALIDATED, Id: s.opts.Id, Token: s.currentToken})
}

func (s *ClientState) SendClientStarted() error {
	return s.send(MsgContent{Name: CLIENT_STARTED, Id: s.opts.Id})
}

func (s *ClientState) NewMaster(server string) {
	logInfo("setting new master: %s", server)
	s.currentMaster = NewRedisShim(server)
}

func (s *ClientState) DetermineInitialMaster() {
	if !MasterFileExists(opts.RedisMasterFile) {
		return
	}
	server := ReadRedisMasterFile(opts.RedisMasterFile)
	if server != "" {
		s.NewMaster(server)
	}
}

func (s *ClientState) Invalidate(msg MsgContent) error {
	if s.RedeemToken(msg.Token) && (s.currentMaster == nil || s.currentMaster.Role() != MASTER) {
		s.currentMaster = nil
		ClearRedisMasterFile(s.opts.RedisMasterFile)
		logInfo("Sending client_invalidated message with id '%s' and token '%s'", s.opts.Id, s.currentToken)
		return s.SendClientInvalidated()
	}
	return nil
}

func (s *ClientState) Reconfigure(msg MsgContent) error {
	logInfo("Received reconfigure message with token %s", msg.Token)
	if !s.RedeemToken(msg.Token) {
		logInfo("Received invalid or outdated token: %s", msg.Token)
	}
	if msg.Server != ReadRedisMasterFile(s.opts.RedisMasterFile) {
		s.NewMaster(msg.Server)
		WriteRedisMasterFile(s.opts.RedisMasterFile, msg.Server)
	}
	return nil
}

func (s *ClientState) Reader() {
	defer func() { s.readerDone <- struct{}{} }()
	defer s.Close()
	for !interrupted {
		msgType, bytes, err := s.ws.ReadMessage()
		atomic.AddInt64(&processed, 1)
		if err != nil || msgType != websocket.TextMessage {
			logError("error reading from server socket: %s", err)
			return
		}
		logDebug("received: %s", string(bytes))
		var body MsgContent
		err = json.Unmarshal(bytes, &body)
		if err != nil {
			logError("reader: could not parse msg: %s", err)
			return
		}
		s.input <- body
	}
}

func (s *ClientState) Writer() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	defer func() { s.writerDone <- struct{}{} }()
	i := 0
	var err error
	for !interrupted {
		select {
		case msg := <-s.input:
			err = s.Dispatch(msg)
		case <-ticker.C:
			i = (i + 1) % s.opts.HeartbeatInterval
			if i == 0 {
				err = s.SendHeartBeat()
			}
		case <-s.readerDone:
			return
		}
		if err != nil {
			return
		}
	}
}

func (s *ClientState) Dispatch(msg MsgContent) error {
	logDebug("dispatcher received: %+v", msg)
	switch msg.Name {
	case RECONFIGURE:
		return s.Reconfigure(msg)
	case PING:
		return s.Ping(msg)
	case INVALIDATE:
		return s.Invalidate(msg)
	default:
		logError("unexpected message: %s", msg.Name)
	}
	return nil
}

func (s *ClientState) Run() error {
	s.DetermineInitialMaster()
	if s.currentMaster == nil || !s.currentMaster.IsMaster() {
		logInfo("clearing master file")
		ClearRedisMasterFile(s.opts.RedisMasterFile)
	}

	if err := s.Connect(); err != nil {
		return err
	}
	if err := VerifyMasterFileString(s.opts.RedisMasterFile); err != nil {
		return err
	}
	if err := s.SendClientStarted(); err != nil {
		return err
	}

	go s.Writer()
	s.Reader()

	select {
	case <-s.writerDone:
		logInfo("writer finished cleanly")
	case <-time.After(2 * time.Second):
		logWarn("clean writer shutdown timed out after 2 seconds")
	}
	return nil
}

func RunConfigurationClient(o ClientOptions) error {
	logInfo("client started with options: %+v\n", o)
	for !interrupted {
		addr := fmt.Sprintf("%s:%d", o.Server, o.Port)
		u := url.URL{Scheme: "ws", Host: addr, Path: "/configuration"}
		state := &ClientState{
			opts:       o,
			url:        u.String(),
			readerDone: make(chan struct{}, 1),
			writerDone: make(chan struct{}, 1),
		}
		state.input = make(chan MsgContent, 1000)
		err := state.Run()
		if err != nil {
			logError("%s", err)
			if !interrupted {
				time.Sleep(3 * time.Second)
			}
		}
	}
	return nil
}
