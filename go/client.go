package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/xing/beetle/consul"
	"gopkg.in/gorilla/websocket.v1"
)

// ClientOptions consist of the id by which the client identifies itself with
// the server, the overall configuration and pointer to a ConsulClient.
type ClientOptions struct {
	Id           string
	Config       *Config
	ConsulClient *consul.Client
}

// ClientState holds the client state.
type ClientState struct {
	opts          ClientOptions
	mutex         sync.Mutex
	ws            *websocket.Conn
	input         chan MsgBody
	currentMaster *RedisShim
	currentToken  string
	writerDone    chan struct{}
	readerDone    chan struct{}
	configChanges chan consul.Env
}

// GetConfig returns the client configuration in a thread safe way.
func (s *ClientState) GetConfig() *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.opts.Config
}

// SetConfig sets replaces the current config with a new one in athread safe way
// and returns the old config.
func (s *ClientState) SetConfig(config *Config) *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	oldconfig := s.opts.Config
	s.opts.Config = config
	return oldconfig
}

// ServerUrl constructs the webesocker URL to contact the server.
func (s *ClientState) ServerUrl() string {
	config := s.GetConfig()
	addr := fmt.Sprintf("%s:%d", config.Server, config.Port)
	u := url.URL{Scheme: "ws", Host: addr, Path: "/configuration"}
	return u.String()
}

// Connect establishes a webscket connection to the server.
func (s *ClientState) Connect() (err error) {
	url := s.ServerUrl()
	websocket.DefaultDialer.HandshakeTimeout = time.Duration(s.GetConfig().DialTimeout) * time.Second
	logInfo("connecting to %s, timeout: %s", url, websocket.DefaultDialer.HandshakeTimeout)
	s.ws, _, err = websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		return
	}
	logInfo("established web socket connection")
	return
}

// Close sends a Close message to the server and closed the connection.
func (s *ClientState) Close() {
	defer s.ws.Close()
	err := s.ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	if err != nil {
		logError("writing websocket close failed: %s", err)
	}
}

// Send a message to the server.
func (s *ClientState) send(msg MsgBody) error {
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

// SendHeartBeat sneds a heartbeat message to the server.
func (s *ClientState) SendHeartBeat() error {
	return s.send(MsgBody{Name: HEARTBEAT, Id: s.opts.Id})
}

// Ping sends a PING message to the server.
func (s *ClientState) Ping(pingMsg MsgBody) error {
	logInfo("Received ping message")
	if s.RedeemToken(pingMsg.Token) {
		return s.SendPong()
	}
	return nil
}

// RedeemToken checks the validity of the given token.
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

// SendPong sends a PONG message to the server.
func (s *ClientState) SendPong() error {
	return s.send(MsgBody{Name: PONG, Id: s.opts.Id, Token: s.currentToken})
}

// SendClientInvalidated sends a CLIENT_INVALIDATED message to the server.
func (s *ClientState) SendClientInvalidated() error {
	return s.send(MsgBody{Name: CLIENT_INVALIDATED, Id: s.opts.Id, Token: s.currentToken})
}

// SendClientStarted sends a CLIENT_STARTED message to the server.
func (s *ClientState) SendClientStarted() error {
	return s.send(MsgBody{Name: CLIENT_STARTED, Id: s.opts.Id})
}

// NewMaster modifies the client state by setting the current master to a new
// one.
func (s *ClientState) NewMaster(server string) {
	logInfo("setting new master: %s", server)
	s.currentMaster = NewRedisShim(server)
}

// DetermineInitialMaster tries to read the current master from disk.
func (s *ClientState) DetermineInitialMaster() {
	if !MasterFileExists(s.GetConfig().RedisMasterFile) {
		return
	}
	server := ReadRedisMasterFile(s.GetConfig().RedisMasterFile)
	if server != "" {
		s.NewMaster(server)
	}
}

// Invalidate clears the redis master file contents and sends a
// CLIENT_INVALIDATED message to the server, provided the token sent with the
// message is valid.
func (s *ClientState) Invalidate(msg MsgBody) error {
	if s.RedeemToken(msg.Token) && (s.currentMaster == nil || s.currentMaster.Role() != MASTER) {
		s.currentMaster = nil
		ClearRedisMasterFile(s.GetConfig().RedisMasterFile)
		logInfo("Sending client_invalidated message with id '%s' and token '%s'", s.opts.Id, s.currentToken)
		return s.SendClientInvalidated()
	}
	return nil
}

// Reconfigure updates the redis mater file on disk, provided the token sent
// with the message is valid.
func (s *ClientState) Reconfigure(msg MsgBody) error {
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

// Reader reads messages from the server and forwards them on an internal
// channel to the Writer, which acts as a message dispatcher. It exits when
// reading results in an error or when the server closes the socket.
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
		var body MsgBody
		err = json.Unmarshal(bytes, &body)
		if err != nil {
			logError("reader: could not parse msg: %s", err)
			return
		}
		s.input <- body
	}
}

// Writer reads messages from an internal channel and dispatches them. It
// peridocally sends a HERATBEAT message to the server. It if receives a config
// change message, it replaces the current config with the new one. If the
// config change implies that the server URL has changed it exits, relying on
// the outer loop to restart the client.
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

// Dispatch dispatches matches rceived from the server to appropriate methods.
func (s *ClientState) Dispatch(msg MsgBody) error {
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

// Run establishes a websocket connection to the server, starts reader and
// writer routines and a consul watcher for config changes. It exits when the
// writer exits.
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

// RunConfigurationClient keeps a client running until the process receives an
// INT or a TERM signal.
func RunConfigurationClient(o ClientOptions) error {
	logInfo("client started with options: %+v\n", o)
	for !interrupted {
		state := &ClientState{
			opts:       o,
			readerDone: make(chan struct{}, 1),
			writerDone: make(chan struct{}, 1),
		}
		state.input = make(chan MsgBody, 1000)
		err := state.Run()
		if err != nil {
			logError("%s", err)
			if !interrupted {
				// TODO: exponential backoff with jitter.
				time.Sleep(1 * time.Second)
			}
		}
	}
	logInfo("client terminated")
	return nil
}
