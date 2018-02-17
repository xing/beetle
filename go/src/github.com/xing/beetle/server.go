package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"text/template"
	"time"

	// "github.com/davecgh/go-spew/spew"
	"github.com/xing/beetle/consul"
	"gopkg.in/gorilla/websocket.v1"
	"gopkg.in/tylerb/graceful.v1"
)

// ServerOptions for our server.
type ServerOptions struct {
	Config       *Config
	ConsulClient *consul.Client
}

// StringChannel is a channel for strings.
type StringChannel chan string

// ChannelMap maps client ids to string channels.
type ChannelMap map[string]StringChannel

// ChannelSet is a set of StringChannels.
type ChannelSet map[StringChannel]StringChannel

// TimeSet maps client ids to last seen times.
type TimeSet map[string]time.Time

// Equal checks whether two timesets are identical.
func (s1 TimeSet) Equal(s2 TimeSet) bool {
	if len(s1) != len(s2) {
		return false
	}
	for k, v := range s1 {
		if !v.Equal(s2[k]) {
			return false
		}
	}
	return true
}

// ServerState holds the server state. TODO: this beast has too many variables.
type ServerState struct {
	opts                         ServerOptions      // Options passed to the constructor.
	mutex                        sync.Mutex         // Mutex for changing opts.Config.
	clientIds                    StringSet          // The list of clients we know and which take part in master election.
	clientChannels               ChannelMap         // Channels we use to communicate with client websocket goroutines.
	notificationChannels         ChannelSet         // Channels we use to communicate with notifier websockets goroutines.
	unknownClientIds             StringList         // List of clients we have seen, but don't know.
	clientsLastSeen              TimeSet            // For any client we have seen, the time when we've last seen him.
	wsChannel                    chan *WsMsg        // Channel used by websocket go routines to send messages to dispatcher go routine.
	upgrader                     websocket.Upgrader // Upgrader to use for turning a http connection into a webscoket connection.
	redis                        *RedisServerInfo   // Cached state of watched redis insiances. Refreshed every RedisMasterRetryInterval seconds.
	currentMaster                *RedisShim         // Current redis master.
	currentTokenInt              int                // Token to identify election rounds.
	currentToken                 string             // String representation of current token.
	clientPongIdsReceived        StringSet          // During a pong phase, the set of clients which have answered.
	clientInvalidatedIdsReceived StringSet          // During the invalidation phase, the set of clients which have answered.
	timerChannel                 chan string        // Channel used to send an abort message to the dispatcher go routine.
	invalidateTimer              *time.Timer        // Timer used to abort waiting for answers from all clients (invalidate/invalidated).
	availabilityTimer            *time.Timer        // Timer used to abort waiting for answers from all clients (ping/pong).
	retries                      int                // Count down for checking a master to come back after it has become unreachable.
	watching                     bool               // Whether we're currently watching a redis master (false during election process).
	watchTick                    int                // One second tick counter which gets reset every RedisMasterRetryInterval seconds.
	waitGroup                    sync.WaitGroup     // Used to organize the shutdown process.
	configChanges                chan consul.Env    // Environment chnages from consul arrive on this channel.
}

// GetConfig returns the server state in a thread safe manner.
func (s *ServerState) GetConfig() *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.opts.Config
}

// SetConfig sets the server state in a thread safe manner.
func (s *ServerState) SetConfig(config *Config) *Config {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	oldconfig := s.opts.Config
	s.opts.Config = config
	return oldconfig
}

// ServerStatus is used to faciliate JSON conversion of parts of the server state.
type ServerStatus struct {
	BeetleVersion          string   `json:"beetle_version"`
	ConfiguredClientIds    []string `json:"configured_client_ids"`
	ConfiguredRedisServers []string `json:"configured_redis_servers"`
	RedisMaster            string   `json:"redis_master"`
	RedisMasterAvailable   bool     `json:"redis_master_available"`
	RedisSlavesAvailable   []string `json:"redis_slaves_available"`
	SwitchInProgress       bool     `json:"switch_in_progress"`
	UnknownClientIds       []string `json:"unknown_client_ids"`
	UnresponsiveClients    []string `json:"unresponsive_clients"`
	UnseenClientIds        []string `json:"unseen_client_ids"`
}

// GetStatus creates a ServerStatus from the curretn server state.
func (s *ServerState) GetStatus() *ServerStatus {
	return &ServerStatus{
		BeetleVersion:          BEETLE_VERSION,
		ConfiguredClientIds:    s.clientIds.Keys(),
		ConfiguredRedisServers: s.redis.instances.Servers(),
		RedisMaster:            s.currentMaster.server,
		RedisMasterAvailable:   s.MasterIsAvailable(),
		RedisSlavesAvailable:   s.redis.Slaves().Servers(),
		SwitchInProgress:       s.WatcherPaused(),
		UnknownClientIds:       s.UnknownClientIds(),
		UnresponsiveClients:    s.UnresponsiveClients(),
		UnseenClientIds:        s.UnseenClientIds(),
	}
}

// pst and psta facilitate sorting of (string, time.Duration pairs) by duration,
// then string value.
type pst struct {
	c string
	t time.Duration
}
type psta []pst

func (a psta) Len() int {
	return len(a)
}

func (a psta) Less(i, j int) bool {
	return a[i].t < a[j].t || (a[i].t == a[j].t && a[i].c < a[j].c)
}

func (a psta) Swap(i, j int) {
	a[i], a[j] = a[j], a[i]
}

// UnresponsiveClients returns a list of client ids from which we haven't heard
// for longer than the configured client timeout.
func (s *ServerState) UnresponsiveClients() []string {
	res := make([]string, 0)
	now := time.Now()
	threshold := now.Add(-(time.Duration(s.GetConfig().ClientTimeout) * time.Second))
	a := make(psta, 0)
	for c, t := range s.clientsLastSeen {
		if t.Before(threshold) {
			a = append(a, pst{c: c, t: now.Sub(t)})
		}
	}
	sort.Sort(sort.Reverse(a))
	for _, x := range a {
		if rounded := x.t.Truncate(time.Second); rounded > 0 {
			res = append(res, fmt.Sprintf("%s: last seen %s ago", x.c, rounded))
		}
	}
	return res
}

// UnseenClientIds returns a list of client ids which have been configured, but
// never sent us anything.
func (s *ServerState) UnseenClientIds() []string {
	res := make([]string, 0)
	for x := range s.clientIds {
		_, found := s.clientsLastSeen[x]
		if !found {
			res = append(res, x)
		}
	}
	sort.Strings(res)
	return res
}

// UnknownClientIds returns a list of client ids which we have senn, but which
// aren't configured.
func (s *ServerState) UnknownClientIds() []string {
	l := len(s.unknownClientIds)
	res := make([]string, l, l)
	copy(res, s.unknownClientIds)
	sort.Strings(res)
	return res
}

var errChannelBlocked = errors.New("channel blocked")

// StringSet implements convenient set abstractions.
type StringSet map[string]bool

// Keys returns the keys of a StringSet as a sorted string slice.
func (l *StringSet) Keys() []string {
	keys := make([]string, 0, len(*l))
	for k := range *l {
		keys = append(keys, k)
	}
	sort.Sort(sort.StringSlice(keys))
	return keys
}

// Include checks whether a given string s is in the set l.
func (l *StringSet) Include(s string) bool {
	_, ok := (*l)[s]
	return ok
}

// Add adds a string s to stringset l.
func (l *StringSet) Add(s string) {
	if !l.Include(s) {
		(*l)[s] = true
	}
}

// Equals checks whether two string sets are equal.
func (l StringSet) Equals(s StringSet) bool {
	if len(l) != len(s) {
		return false
	}
	for x := range l {
		if !s.Include(x) {
			return false
		}
	}
	return true
}

// StringList implements convenience functions on string slices.
type StringList []string

// Include check whether a given string s is included in string slice l.
func (l *StringList) Include(s string) bool {
	for _, x := range *l {
		if x == s {
			return true
		}
	}
	return false
}

// Add adds a given string s to the end of string slice l.
func (l *StringList) Add(s string) {
	if (*l).Include(s) {
		return
	}
	*l = append(*l, s)
}

// AddClient registers a communication channel for a given client id.
func (s *ServerState) AddClient(name string, channel StringChannel) {
	s.clientChannels[name] = channel
}

// RemoveClient unregisters a communication channel for a given client id.
func (s *ServerState) RemoveClient(name string) {
	delete(s.clientChannels, name)
}

// AddNotification registers a notification channel.
func (s *ServerState) AddNotification(channel StringChannel) {
	s.notificationChannels[channel] = channel
}

// RemoveNotification unregisters a notification channel.
func (s *ServerState) RemoveNotification(channel StringChannel) {
	delete(s.notificationChannels, channel)
}

// ClientTimeout returns the client timeout as a time.Duration.
func (s *ServerState) ClientTimeout() time.Duration {
	return time.Duration(s.GetConfig().ClientTimeout) * time.Second
}

// SendToWebSockets sends a message to all registered clients channels.
func (s *ServerState) SendToWebSockets(msg *MsgBody) (err error) {
	data, err := json.Marshal(msg)
	if err != nil {
		logError("Could not marshal message")
		return
	}
	logDebug("Sending message to %d clients: %s", len(s.clientChannels), string(data))
	for _, c := range s.clientChannels {
		select {
		case c <- string(data):
		default:
			err = errChannelBlocked
		}
	}
	return
}

// SendNotification sends a notifcation on all registered notifcation channels.
func (s *ServerState) SendNotification(text string) (err error) {
	logInfo("Sending notification to %d subscribers", len(s.notificationChannels))
	for c := range s.notificationChannels {
		select {
		case c <- text:
		default:
			err = errChannelBlocked
		}
	}
	return
}

// String constants used as message identifiers.
const (
	// internal messages
	UNSUBSCRIBE = "unsubscribe"
	// messages sent
	PING                = "ping"
	INVALIDATE          = "invalidate"
	RECONFIGURE         = "reconfigure"
	SYSTEM_NOTIFICATION = "system_notification"
	// messages received
	CLIENT_STARTED     = "client_started"
	PONG               = "pong"
	CLIENT_INVALIDATED = "client_invalidated"
	HEARTBEAT          = "heartbeat"
	START_NOTIFY       = "start_notify"
	STOP_NOTIFY        = "stop_notify"
	// timer message
	CANCEL_INVALIDATION = "cancel_invalidation"
	CHECK_AVAILABILITY  = "check_availability"
)

// MsgBody facilitates JSON conversion for messages sent btween client and server.
type MsgBody struct {
	Name   string `json:"name"`
	Id     string `json:"id,omitempty"`
	Token  string `json:"token,omitempty"`
	Server string `json:"server,omitempty"`
}

// WsMsg bundles a MsgBody and a string channel.
type WsMsg struct {
	body    MsgBody
	channel chan string
}

func (s *ServerState) dispatcher() {
	ticker := time.NewTicker(1 * time.Second)
	s.StartWatcher()
	for !interrupted {
		select {
		case msg := <-s.wsChannel:
			s.handleWebSocketMsg(msg)
		case <-s.timerChannel:
			s.CancelInvalidation()
		case <-ticker.C:
			s.watchTick = (s.watchTick + 1) % s.GetConfig().RedisMasterRetryInterval
			if s.watchTick == 0 {
				s.CheckRedisAvailability()
				s.ForgetOldUnknownClientIds()
				s.ForgetOldLastSeenEntries()
			}
		case env := <-s.configChanges:
			newconfig := buildConfig(env)
			s.SetConfig(newconfig)
			logInfo("updated server config from consul: %s", s.GetConfig())
		}
	}
}

func (s *ServerState) handleWebSocketMsg(msg *WsMsg) {
	logDebug("dipatcher received %+v", msg.body)
	switch msg.body.Name {
	case CLIENT_STARTED:
		logDebug("Adding client %s", msg.body.Id)
		s.AddClient(msg.body.Id, msg.channel)
		s.ClientStarted(msg.body)
	case UNSUBSCRIBE:
		logDebug("Removing client %s", msg.body.Id)
		s.RemoveClient(msg.body.Id)
		close(msg.channel)
	case START_NOTIFY:
		logDebug("Adding notification %s", msg.body.Id)
		s.AddNotification(msg.channel)
	case STOP_NOTIFY:
		logDebug("Removing notification %s", msg.body.Id)
		s.RemoveNotification(msg.channel)
		close(msg.channel)
	case HEARTBEAT:
		s.Heartbeat(msg.body)
	case PONG:
		s.Pong(msg.body)
	case CLIENT_INVALIDATED:
		s.ClientInvalidated(msg.body)
	default:
		logError("received unknown message: %s", msg.body.Name)
	}
}

// NewServerState creates partially initialized ServerState.
func NewServerState(o ServerOptions) *ServerState {
	s := &ServerState{clientChannels: make(ChannelMap), notificationChannels: make(ChannelSet)}
	s.opts = o
	s.redis = NewRedisServerInfo(s.GetConfig().RedisServers)
	s.upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(r *http.Request) bool { return true },
	}
	s.wsChannel = make(chan *WsMsg, 10000)
	s.clientIds = make(StringSet)
	for _, id := range strings.Split(s.GetConfig().ClientIds, ",") {
		if id != "" {
			s.clientIds.Add(id)
		}
	}
	s.unknownClientIds = make(StringList, 0)
	s.clientsLastSeen = make(TimeSet)
	s.currentTokenInt = int(time.Now().UnixNano() / 1000000) // millisecond resolution
	s.currentToken = strconv.Itoa(s.currentTokenInt)
	s.clientPongIdsReceived = make(StringSet)
	s.clientInvalidatedIdsReceived = make(StringSet)
	return s
}

// SaveState stores some aspects of the server state to the current redis master
// to avoid re-sending notifications on restart.
func (s *ServerState) SaveState() {
	if s.currentMaster == nil {
		logError("could not save state because no redis master is available")
		return
	}
	lastSeen := make([]string, 0)
	for id, t := range s.clientsLastSeen {
		lastSeen = append(lastSeen, fmt.Sprintf("%s:%d", id, t.UnixNano()))
	}
	lastSeenStr := strings.Join(lastSeen, ",")
	_, err := s.currentMaster.redis.Set("beetle:clients-last-seen", lastSeenStr, 0).Result()
	if err != nil {
		logError("could not save clients last seen info to redis")
	}
	logDebug("saved last seen info to redis: %s", lastSeenStr)
}

// LoadState loads previously saved state from current redis master.
func (s *ServerState) LoadState() {
	if s.currentMaster == nil {
		logError("could not restore state because we have no redis master")
		return
	}
	v, err := s.currentMaster.redis.Get("beetle:clients-last-seen").Result()
	if err != nil {
		logError("could not load last seen info from redis")
	}
	for _, x := range strings.Split(v, ",") {
		if x != "" {
			parts := strings.Split(x, ":")
			id, t := parts[0], parts[1]
			i, err := strconv.Atoi(t)
			if err != nil {
				logError("could not recreate timestamp for id '%s': %s", id, t)
			} else {
				s.clientsLastSeen[id] = time.Unix(0, int64(i))
			}
		}
	}
	logInfo("restored client last seen info from redis: %v", s.clientsLastSeen)
}

// waits on a sync.WaitGroup, but times out after given duration.
func waitForWaitGroupWithTimeout(wg *sync.WaitGroup, timeout time.Duration) bool {
	c := make(chan struct{})
	go func() {
		defer close(c)
		wg.Wait()
	}()
	select {
	case <-c:
		return false
	case <-time.After(timeout):
		return true
	}
}

// RunConfigurationServer implements the main server loop.
func RunConfigurationServer(o ServerOptions) error {
	logInfo("server started with options: %+v\n", o)
	state := NewServerState(o)
	state.Initialize()
	// start threads
	go state.dispatcher()
	if Verbose {
		go state.statsReporter()
	}
	if state.opts.ConsulClient != nil {
		var err error
		state.configChanges, err = state.opts.ConsulClient.WatchConfig()
		if err != nil {
			return err
		}
	} else {
		state.configChanges = make(chan consul.Env)
	}

	state.clientHandler(state.GetConfig().Port)
	logInfo("shutting down")
	// wait for web socket readers and writers to finish
	if waitForWaitGroupWithTimeout(&state.waitGroup, 3*time.Second) {
		logInfo("websocket readers and writers shut down timed out")
	} else {
		logInfo("websocket readers and writers finished cleanly")
	}
	return nil
}

var (
	processed     int64
	wsConnections int64
)

func (s *ServerState) clientHandler(webSocketPort int) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.dispatchRequest)
	logInfo("Starting web socket server on port %d", webSocketPort)
	webSocketSpec := ":" + strconv.Itoa(webSocketPort)
	graceful.Run(webSocketSpec, 10*time.Second, mux)
}

func (s *ServerState) serveNotifications(w http.ResponseWriter, r *http.Request) {
	logDebug("received notification request")
	ws, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		if _, ok := err.(websocket.HandshakeError); !ok {
			logError(err.Error())
		}
		return
	}
	defer ws.Close()
	s.notificationReader(ws)
}

func (s *ServerState) notificationReader(ws *websocket.Conn) {
	var dispatcherInput = make(chan string, 1000)
	// channel dispatcher_input will be closed by dispatcher, to avoid sending on a closed channel
	s.wsChannel <- &WsMsg{body: MsgBody{Name: START_NOTIFY}, channel: dispatcherInput}
	go s.notificationWriter(ws, dispatcherInput)
	for !interrupted {
		msgType, bytes, err := ws.ReadMessage()
		if err != nil || msgType != websocket.TextMessage {
			logError("notificationReader: could not read msg: %s", err)
			break
		}
		logInfo("ignored message from notification subscriber: %s", string(bytes))
	}
	s.wsChannel <- &WsMsg{body: MsgBody{Name: STOP_NOTIFY}, channel: dispatcherInput}
}

func (s *ServerState) notificationWriter(ws *websocket.Conn, inputFromDispatcher chan string) {
	s.waitGroup.Add(1)
	defer s.waitGroup.Done()
	for !interrupted {
		select {
		case data, ok := <-inputFromDispatcher:
			if !ok {
				logInfo("Terminating notification websocket writer")
				return
			}
			ws.WriteMessage(websocket.TextMessage, []byte(data))
		case <-time.After(100 * time.Millisecond):
			// give the outer loop a chance to detect interrupts (without doing a busy wait)
		}
	}
}

func (s *ServerState) serveWs(w http.ResponseWriter, r *http.Request) {
	logDebug("received web socket request")
	atomic.AddInt64(&wsConnections, 1)
	ws, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		if _, ok := err.(websocket.HandshakeError); !ok {
			logError(err.Error())
		}
		return
	}
	defer ws.Close()
	defer (func() {
		atomic.AddInt64(&wsConnections, -1)
	})()
	s.wsReader(ws)
}

// HtmlTemplate defines how the web UI looks.
const HtmlTemplate = `
<!doctype html>
<html><head><title>Beetle Configuration Server Status</title>
<style media="screen" type="text/css">
html { font: 1.25em/1.5 arial, sans-serif;}
body { margin: 1em; }
table tr:nth-child(2n+1){ background-color: #ffffff; }
td { padding: 0.1em 0.2em; vertical-align: top; }
ul { list-style-type: none; margin: 0; padding: 0;}
li { }
{{ if .RedisMasterAvailable }}
h1 { color: #5780b2; margin-bottom: 0.2em;}
{{ else }}
h1 { color: #A52A2A; margin-bottom: 0.2em;}
{{ end }}
a:link, a:visited {text-decoration:none; color:#A52A2A;}
a:hover, a:active {text-decoration:none; color:#FF0000;}
a {
  padding: 10px; background: #cdcdcd;
  -moz-border-radius: 5px;
   border-radius: 5px;
  -moz-box-shadow: 2px 2px 2px #bbb;
  -webkit-box-shadow: 2px 2px 2px #bbb;
  box-shadow: 2px 2px 2px #bbb;
}
form { font-size: 1em; margin-bottom: 1em; }
</style></head>
<body><h1>Beetle Configuration Server Status</h1>
{{ if not .RedisMasterAvailable }}
<form name='masterswitch' method='post' action='/initiate_master_switch'>
Master down!
<a href='javascript: document.masterswitch.submit();'>Initiate master switch</a>
or wait until system performs it automatically.
</form>
{{ end }}
<table cellspacing=0>
<tr><td>unseen_client_ids</td><td><ul>{{ if not .UnseenClientIds }}none{{ else }}{{ range .UnseenClientIds }}<li>{{ . }}</li>{{ end }}{{ end }}</ul></td></tr>
<tr><td>unresponsive_clients</td><td><ul>{{ if not .UnresponsiveClients }}none{{ else }}{{ range .UnresponsiveClients }}<li>{{ . }}</li>{{ end }}{{ end }}</ul></td></tr>
<tr><td>unknown_client_ids</td><td><ul>{{ if not .UnknownClientIds }}none{{ else }}{{ range .UnknownClientIds }}<li>{{ . }}</li>{{ end }}{{ end }}</ul></td></tr>
<tr><td>switch_in_progress</td><td>{{ .SwitchInProgress}}</td></tr>
<tr><td>redis_slaves_available</td><td><ul>{{ if not .RedisSlavesAvailable }}none{{ else }}{{ range .RedisSlavesAvailable }}<li>{{ . }}</li>{{ end }}{{ end }}</ul></td></tr>
<tr><td>redis_master_available</td><td><ul>{{ .RedisMasterAvailable }}</td></tr>
<tr><td>redis_master</td><td>{{ .RedisMaster}}</td></tr>
<tr><td>configured_redis_servers</td><td><ul>{{ range .ConfiguredRedisServers }}<li>{{ . }}</li>{{ end }}</ul></td></tr>
<tr><td>configured_client_ids</td><td><ul>{{ range .ConfiguredClientIds }}<li>{{ . }}</li>{{ end }}</ul></td></tr>
<tr><td>beetle_version</td><td>{{ .BeetleVersion}}</td></tr>
</table>
</body></html>
`

func (s *ServerState) dispatchRequest(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/", "/.html":
		w.Header().Set("Content-Type", "text/html")
		tmpl, err := template.New("server").Parse(HtmlTemplate)
		if err != nil {
			w.WriteHeader(500)
			return
		}
		err = tmpl.Execute(w, s.GetStatus())
		if err != nil {
			w.WriteHeader(500)
			return
		}
	case "/.json":
		w.Header().Set("Content-Type", "application/json")
		b, err := json.Marshal(s.GetStatus())
		if err != nil {
			w.WriteHeader(500)
			return
		}
		fmt.Fprintf(w, "%s", string(b))
	case "/.txt":
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "Not yet implemented")
	case "/initiate_master_switch":
		w.Header().Set("Content-Type", "text/plain")
		s.initiateMasterSwitch(w, r)
	case "/brokers":
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "[]")
	case "/configuration":
		s.serveWs(w, r)
	case "/notifications":
		s.serveNotifications(w, r)
	default:
		http.NotFound(w, r)
	}
}

func (s *ServerState) initiateMasterSwitch(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	if s.InitiateMasterSwitch() {
		w.WriteHeader(201)
		fmt.Println(w, "Master switch initiated")
	} else {
		w.WriteHeader(200)
		fmt.Println(w, "No master switch necessary")
	}
}

func (s *ServerState) wsReader(ws *websocket.Conn) {
	var dispatcherInput = make(chan string, 1000)
	// channel will be closed by dispatcher, to avoid sending on a closed channel

	var channelName string
	writerStarted := false
	var body MsgBody

	for !interrupted {
		msgType, bytes, err := ws.ReadMessage()
		atomic.AddInt64(&processed, 1)
		if err != nil || msgType != websocket.TextMessage {
			logError("wsReader: could not read msg: %s", err)
			break
		}
		err = json.Unmarshal(bytes, &body)
		if err != nil {
			logError("wsReader: could not parse msg, error=%s: %s", err, string(bytes))
			break
		}
		if !writerStarted {
			channelName = body.Id
			logInfo("starting web socket writer for client %s", body.Id)
			go s.wsWriter(channelName, ws, dispatcherInput)
			writerStarted = true
		}
		logDebug("received %s", string(bytes))
		s.wsChannel <- &WsMsg{body: body, channel: dispatcherInput}
	}
	s.wsChannel <- &WsMsg{body: MsgBody{Name: UNSUBSCRIBE, Id: channelName}, channel: dispatcherInput}
}

func (s *ServerState) wsWriter(clientID string, ws *websocket.Conn, inputFromDispatcher chan string) {
	s.waitGroup.Add(1)
	defer s.waitGroup.Done()
	defer ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(1000, "good bye"))
	for !interrupted {
		select {
		case data, ok := <-inputFromDispatcher:
			if !ok {
				logInfo("Closed channel for %s", clientID)
				return
			}
			ws.WriteMessage(websocket.TextMessage, []byte(data))
		case <-time.After(100 * time.Millisecond):
			// give the outer loop a chance to detect interrupts
		}
	}
}

// Initialize completes the state initialization by checking redis connectivity
// and loading saved state.
func (s *ServerState) Initialize() {
	VerifyMasterFileString(s.GetConfig().RedisMasterFile)
	s.CheckRedisConfiguration()
	s.redis.Refresh()
	s.DetermineInitialMaster()
	if s.currentMaster == nil {
		logError("Could not determine initial master")
		os.Exit(1)
	}
	s.LoadState()
	s.ForgetOldUnknownClientIds()
	s.ForgetOldLastSeenEntries()
}

// Pong handles a client's reply to the PING message.
func (s *ServerState) Pong(msg MsgBody) {
	s.ClientSeen(msg.Id)
	if !s.ValidatePongClientId(msg.Id) {
		return
	}
	logInfo("Received pong message from id '%s' with token '%s'", msg.Id, msg.Token)
	if !s.RedeemToken(msg.Token) {
		return
	}
	s.clientPongIdsReceived.Add(msg.Id)
	if s.AllClientPongIdsReceived() {
		logInfo("All client pong ids received!")
		if s.availabilityTimer != nil {
			s.availabilityTimer.Stop()
			s.availabilityTimer = nil
		}
		s.InvalidateCurrentMaster()
	}
}

// ClientStarted handles a client's CLIENT_STARTED message.
func (s *ServerState) ClientStarted(msg MsgBody) {
	seen := s.ClientSeen(msg.Id)
	if s.ClientIdIsValid(msg.Id) {
		logInfo("Received client_started message from id '%s'", msg.Id)
	} else {
		s.AddUnknownClientId(msg.Id)
		if !seen {
			msg := fmt.Sprintf("Received client_started message from unknown id '%s'", msg.Id)
			logError(msg)
			s.SendNotification(msg)
		}
	}
}

// Heartbeat handles a client's HEARTBEAT message.
func (s *ServerState) Heartbeat(msg MsgBody) {
	seen := s.ClientSeen(msg.Id)
	if s.ClientIdIsValid(msg.Id) {
		logDebug("received heartbeat message from id '%s'", msg.Id)
	} else {
		s.AddUnknownClientId(msg.Id)
		if !seen {
			msg := fmt.Sprintf("Received heartbeat message from unknown id '%s'", msg.Id)
			logError(msg)
			s.SendNotification(msg)
		}
	}
}

// ClientInvalidated handles a client's CLIENT_INVALIDATED message.
func (s *ServerState) ClientInvalidated(msg MsgBody) {
	s.ClientSeen(msg.Id)
	if !s.ClientIdIsValid(msg.Id) {
		s.AddUnknownClientId(msg.Id)
	}
	logInfo("Received client_invalidated message from id '%s' with token '%s'", msg.Id, msg.Token)
	s.clientInvalidatedIdsReceived.Add(msg.Id)
	if s.AllClientInvalidatedIdsReceived() {
		logInfo("All client invalidated ids received")
		if s.invalidateTimer != nil {
			s.invalidateTimer.Stop()
			s.invalidateTimer = nil
		}
		s.SwitchMaster()
	}
}

// MasterUnavailable pauses the redis watcher, sends a nofication that the redis
// master has become unavailable and starts the voting process on whether to
// switch or not. If no client ids have been configured, it switches the master
// immediately.
func (s *ServerState) MasterUnavailable() {
	s.PauseWatcher()
	msg := fmt.Sprintf("Redis master '%s' not available", s.currentMaster.server)
	logWarn(msg)
	s.SendNotification(msg)
	if len(s.clientIds) == 0 {
		s.SwitchMaster()
	} else {
		s.StartInvalidation()
	}
}

// MasterAvailable send current master info to all connected clients and
// reconfigures remaining redis servers as slaves of the (new) master.
func (s *ServerState) MasterAvailable() {
	s.PublishMaster(s.currentMaster.server)
	s.ConfigureSlaves(s.currentMaster)
	s.SaveState()
}

// MasterIsAvailable uses the cached redis information to determine whether the
// currently configured master is in fact available.
func (s *ServerState) MasterIsAvailable() bool {
	logDebug("Checking master availability. currentMaster: '%+v'", s.currentMaster)
	return s.redis.Masters().Include(s.currentMaster)
}

// AvailableSlaves retrieves the list of slaves from the cached redis
// information.
func (s *ServerState) AvailableSlaves() RedisShims {
	return s.redis.Slaves()
}

// InitiateMasterSwitch refreshes the cached redis information and starts a vote
// on a new redis server, unless there is already a vote in progress or the
// currently configured redis master is available.
func (s *ServerState) InitiateMasterSwitch() bool {
	s.redis.Refresh()
	available, switchInProgress := s.MasterIsAvailable(), s.WatcherPaused()
	logInfo("Initiating master switch: already in progress = %v", switchInProgress)
	if !(available || switchInProgress) {
		s.MasterUnavailable()
	}
	return !available || switchInProgress
}

// MaxUnknownClientIds specifies the maximum number of unknown clients we keep
// information on.
const MaxUnknownClientIds = 1000

// AddUnknownClientId adds a client id to the unknown clients list. It removes
// old entries from the list if the list ist longer than desired, in order to
// protect against memeory overflows caused by client programming errors.
func (s *ServerState) AddUnknownClientId(id string) {
	for len(s.unknownClientIds) >= MaxUnknownClientIds {
		oldId := s.unknownClientIds[0]
		s.unknownClientIds = s.unknownClientIds[1:len(s.unknownClientIds)]
		delete(s.clientsLastSeen, oldId)
	}
	s.unknownClientIds.Add(id)
}

// ForgetOldUnknownClientIds removes entries from the set of unknown client ids
// from which we haven't heard for at least 24 hours.
func (s *ServerState) ForgetOldUnknownClientIds() {
	threshold := time.Now().Add(-24 * time.Hour)
	newUnknown := make(StringList, 0, len(s.unknownClientIds))
	for _, id := range s.unknownClientIds {
		lastSeen, ok := s.clientsLastSeen[id]
		if ok && lastSeen.After(threshold) {
			newUnknown = append(newUnknown, id)
		}
	}
	s.unknownClientIds = newUnknown
}

// ForgetOldLastSeenEntries removes entries from the set of unknown client ids
// from which we haven't heard for at least 24 hours.
func (s *ServerState) ForgetOldLastSeenEntries() {
	threshold := time.Now().Add(-24 * time.Hour)
	newLastSeen := make(TimeSet)
	for id, t := range s.clientsLastSeen {
		if t.After(threshold) {
			newLastSeen[id] = t
		}
	}
	s.clientsLastSeen = newLastSeen
}

// ClientSeen inserts or updates client last seen timestamp. Returns true if we
// have seen the client id previously.
func (s *ServerState) ClientSeen(id string) bool {
	_, seen := s.clientsLastSeen[id]
	s.clientsLastSeen[id] = time.Now()
	return seen
}

// CheckRedisConfiguration checks whether we have at leats two redis servers.
func (s *ServerState) CheckRedisConfiguration() {
	if s.redis.NumServers() < 2 {
		logError("Redis failover needs at least two redis servers")
		os.Exit(1)
	}
}

// DetermineInitialMaster either uses information from the master file on disk
// or tries to auto detect an inital redis master and writes it to disk. If no
// master can be determined, the main server loop will start a vote later on.
func (s *ServerState) DetermineInitialMaster() {
	if MasterFileExists(s.GetConfig().RedisMasterFile) {
		s.currentMaster = RedisMasterFromMasterFile(s.GetConfig().RedisMasterFile)
	}
	if s.currentMaster != nil {
		logInfo("initial master from redis master file: %s", s.currentMaster.server)
		if s.redis.Slaves().Include(s.currentMaster) {
			s.MasterUnavailable()
		} else if s.redis.Unknowns().Include(s.currentMaster) {
			s.MasterUnavailable()
		}
	} else {
		s.currentMaster = s.redis.AutoDetectMaster()
		if s.currentMaster != nil {
			WriteRedisMasterFile(s.GetConfig().RedisMasterFile, s.currentMaster.server)
		}
	}
}

// DetermineNewMaster uses the cached redis information to either select a new
// master from slaves of the current master or simply returns the current
// master, if it can still be reached.
func (s *ServerState) DetermineNewMaster() *RedisShim {
	if s.redis.Unknowns().Include(s.currentMaster) {
		slaves := s.redis.SlavesOf(s.currentMaster)
		if len(slaves) == 0 {
			return nil
		}
		return slaves[0]
	}
	return s.currentMaster
}

// ValidatePongClientId checks whether the given client id has been configured
// as a known id. If it's not, it is added to the set of unknown client ids and
// a notification is sent.
func (s *ServerState) ValidatePongClientId(id string) bool {
	if s.ClientIdIsValid(id) {
		return true
	}
	s.AddUnknownClientId(id)
	msg := fmt.Sprintf("Received pong message from unknown client id '%s'", id)
	logError(msg)
	s.SendNotification(msg)
	return false
}

// ClientIdIsValid checks whether the given client id has been configured.
func (s *ServerState) ClientIdIsValid(id string) bool {
	return s.clientIds.Include(id)
}

// RedeemToken checks whether the given token is valid for the current vote.
func (s *ServerState) RedeemToken(token string) bool {
	if token == s.currentToken {
		return true
	}
	logInfo("Ignored message (token was '%s', but expected '%s'", token, s.currentToken)
	return false
}

// GenerateNewToken generates a new token by incrementing a counter maintained
// in the server state.
func (s *ServerState) GenerateNewToken() {
	s.currentTokenInt++
	s.currentToken = strconv.Itoa(s.currentTokenInt)
}

// StartInvalidation resets the state information used to keep track of the an
// ongoing vote and starts a new vote.
func (s *ServerState) StartInvalidation() {
	s.clientPongIdsReceived = make(StringSet)
	s.clientInvalidatedIdsReceived = make(StringSet)
	s.CheckAllClientsAvailable()
}

// CheckAllClientsAvailable sends a PING message to all connected clients.
func (s *ServerState) CheckAllClientsAvailable() {
	s.GenerateNewToken()
	logInfo("Sending ping messages with token '%s'", s.currentToken)
	msg := &MsgBody{Name: PING, Token: s.currentToken}
	s.SendToWebSockets(msg)
	s.availabilityTimer = time.AfterFunc(s.ClientTimeout(), func() {
		s.availabilityTimer = nil
		s.timerChannel <- CANCEL_INVALIDATION
	})
}

// InvalidateCurrentMaster sends the INVALIDATE message to all connected
// clients.
func (s *ServerState) InvalidateCurrentMaster() {
	s.GenerateNewToken()
	logInfo("Sending invalidate messages with token '%s'", s.currentToken)
	msg := &MsgBody{Name: INVALIDATE, Token: s.currentToken}
	s.SendToWebSockets(msg)
	s.invalidateTimer = time.AfterFunc(s.ClientTimeout(), func() {
		s.invalidateTimer = nil
		s.timerChannel <- CANCEL_INVALIDATION
	})
}

// CancelInvalidation generates a new token to the next vote and unpauses the
// watcher.
func (s *ServerState) CancelInvalidation() {
	s.GenerateNewToken()
	s.StartWatcher()
}

// AllClientPongIdsReceived checks whether all client's have answered the PING
// message by sending a PONG.
func (s *ServerState) AllClientPongIdsReceived() bool {
	return s.clientIds.Equals(s.clientPongIdsReceived)
}

// AllClientInvalidatedIdsReceived checks whether all client's have answered the
// INVALIDATE message by sending a CLIENT_INVALIDATED message back.
func (s *ServerState) AllClientInvalidatedIdsReceived() bool {
	return s.clientIds.Equals(s.clientInvalidatedIdsReceived)
}

// SwitchMaster is called after a successfully completed vote and performs a
// switch to a new master, if possible. If no new master can be determined, it
// starts watching the old master again. In either case, a notification message
// is sent out.
func (s *ServerState) SwitchMaster() {
	newMaster := s.DetermineNewMaster()
	if newMaster != nil {
		msg := fmt.Sprintf("Setting redis master to '%s' (was '%s')", newMaster.server, s.currentMaster.server)
		logWarn(msg)
		s.SendNotification(msg)
		newMaster.MakeMaster()
		WriteRedisMasterFile(s.GetConfig().RedisMasterFile, newMaster.server)
		s.currentMaster = newMaster
	} else {
		msg := fmt.Sprintf("Redis master could not be switched, no slave available to become new master, promoting old master")
		logError(msg)
		s.SendNotification(msg)
	}
	s.PublishMaster(s.currentMaster.server)
	s.StartWatcher()
}

// PublishMaster sends the RECONFIGURE message to all connected clients.
func (s *ServerState) PublishMaster(server string) {
	logInfo("Sending reconfigure message with server '%s' and token: '%s'", server, s.currentToken)
	msg := &MsgBody{Name: RECONFIGURE, Server: server, Token: s.currentToken}
	s.SendToWebSockets(msg)
}

// ConfigureSlaves turns all masters which are not the currently configured
// master into slaves of the current master.
func (s *ServerState) ConfigureSlaves(master *RedisShim) {
	for _, r := range s.redis.Masters() {
		if r.server != master.server {
			r.redis.SlaveOf(master.host, strconv.Itoa(master.port))
		}
	}
	// TODO: shouldn't we also make sure all slaves are slaves of the correct master?
}

// WatcherPaused checks whether the redis watcher has been paused.
func (s *ServerState) WatcherPaused() bool {
	return !s.watching
}

// StartWatcher starts watching the redis server status.
func (s *ServerState) StartWatcher() {
	if s.WatcherPaused() {
		s.watchTick = 0
		s.watching = true
		logInfo("Starting watching redis servers every %d seconds", s.GetConfig().RedisMasterRetryInterval)
	}
}

// PauseWatcher starts watching the redis server status.
func (s *ServerState) PauseWatcher() {
	if s.WatcherPaused() {
		return
	}
	logInfo("Pause checking availability of redis servers")
	s.watching = false
}

// CheckRedisAvailability uses
func (s *ServerState) CheckRedisAvailability() {
	s.redis.Refresh()
	if s.MasterIsAvailable() {
		s.MasterAvailable()
	} else {
		retriesLeft := s.GetConfig().RedisMasterRetries - (s.retries + 1)
		logWarn("Redis master not available! (Retries left: %d)", retriesLeft)
		s.retries++
		if s.retries >= s.GetConfig().RedisMasterRetries {
			s.retries = 0
			s.MasterUnavailable()
		}
	}
}
