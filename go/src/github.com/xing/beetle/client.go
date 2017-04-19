package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"gopkg.in/gorilla/websocket.v1"
	"source.xing.com/olympus/golympus/consul"
)

type ClientOptions struct {
	Id           string
	Config       *Config
	ConsulClient *consul.Client
}

type ClientState struct {
	opts          ClientOptions
	mutex         sync.Mutex
	ws            *websocket.Conn
	input         chan MsgContent
	currentMaster *RedisShim
	currentToken  string
	writerDone    chan struct{}
	readerDone    chan struct{}
	configChanges chan consul.Env
}

func (s *ClientState) GetConfig() *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.opts.Config
}

func (s *ClientState) SetConfig(config *Config) *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	oldconfig := s.opts.Config
	s.opts.Config = config
	return oldconfig
}

func (s *ClientState) ServerUrl() string {
	config := s.GetConfig()
	addr := fmt.Sprintf("%s:%d", config.Server, config.Port)
	u := url.URL{Scheme: "ws", Host: addr, Path: "/configuration"}
	return u.String()
}

func (s *ClientState) Connect() (err error) {
	url := s.ServerUrl()
	logInfo("connecting to %s", url)
	s.ws, _, err = websocket.DefaultDialer.Dial(url, nil)
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
	logDebug("sending message")
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
	if !MasterFileExists(s.GetConfig().RedisMasterFile) {
		return
	}
	server := ReadRedisMasterFile(s.GetConfig().RedisMasterFile)
	if server != "" {
		s.NewMaster(server)
	}
}

func (s *ClientState) Invalidate(msg MsgContent) error {
	if s.RedeemToken(msg.Token) && (s.currentMaster == nil || s.currentMaster.Role() != MASTER) {
		s.currentMaster = nil
		ClearRedisMasterFile(s.GetConfig().RedisMasterFile)
		logInfo("Sending client_invalidated message with id '%s' and token '%s'", s.opts.Id, s.currentToken)
		return s.SendClientInvalidated()
	}
	return nil
}

func (s *ClientState) Reconfigure(msg MsgContent) error {
	logInfo("Received reconfigure message with server '%s' and token '%s'", msg.Server, msg.Token)
	if !s.RedeemToken(msg.Token) {
		logInfo("Received invalid or outdated token: '%s'", msg.Token)
	}
	if msg.Server != ReadRedisMasterFile(s.GetConfig().RedisMasterFile) {
		s.NewMaster(msg.Server)
		WriteRedisMasterFile(s.GetConfig().RedisMasterFile, msg.Server)
	}
	return nil
}

func (s *ClientState) Reader() {
	defer func() { s.readerDone <- struct{}{} }()
	for !interrupted {
		select {
		case <-s.writerDone:
			return
		default:
		}
		logDebug("reading message")
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
	defer s.Close()
	defer ticker.Stop()
	defer func() { s.writerDone <- struct{}{} }()
	i := 0
	var err error
	for !interrupted {
		select {
		case msg := <-s.input:
			err = s.Dispatch(msg)
		case <-ticker.C:
			i = (i + 1) % s.GetConfig().ClientHeartbeat
			if i == 0 {
				err = s.SendHeartBeat()
			}
		case <-s.readerDone:
			return
		case env := <-s.configChanges:
			if env != nil {
				newconfig := buildConfig(env)
				oldconfig := s.SetConfig(newconfig)
				logInfo("updated server config from consul: %s", s.GetConfig())
				if newconfig.RedisMasterFile != oldconfig.RedisMasterFile {
					if err := os.Rename(oldconfig.RedisMasterFile, newconfig.RedisMasterFile); err != nil {
						logError("could not rename redis master file to: %s", newconfig.RedisMasterFile)
					}
				}
				if newconfig.ServerUrl() != oldconfig.ServerUrl() {
					logInfo("restarting client because server url has changed: %s", newconfig.ServerUrl())
					return
				}
			}
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
		ClearRedisMasterFile(s.GetConfig().RedisMasterFile)
	}
	if err := s.Connect(); err != nil {
		return err
	}
	if err := VerifyMasterFileString(s.GetConfig().RedisMasterFile); err != nil {
		return err
	}
	if err := s.SendClientStarted(); err != nil {
		return err
	}
	if s.opts.ConsulClient != nil {
		var err error
		s.configChanges, err = s.opts.ConsulClient.WatchConfig()
		if err != nil {
			return err
		}
	} else {
		s.configChanges = make(chan consul.Env)
	}
	go s.Reader()
	s.Writer()
	return nil
}

func RunConfigurationClient(o ClientOptions) error {
	logInfo("client started with options: %+v\n", o)
	for !interrupted {
		state := &ClientState{
			opts:       o,
			readerDone: make(chan struct{}, 1),
			writerDone: make(chan struct{}, 1),
		}
		state.input = make(chan MsgContent, 1000)
		err := state.Run()
		if err != nil {
			logError("%s", err)
			if !interrupted {
				time.Sleep(1 * time.Second)
			}
		}
	}
	logInfo("client terminated")
	return nil
}
