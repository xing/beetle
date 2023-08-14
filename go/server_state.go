package main

import (
	"context"
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
	"github.com/gorilla/websocket"
	"github.com/xing/beetle/consul"
)

// ServerOptions for our server.
type ServerOptions struct {
	Config       *Config
	ConsulClient *consul.Client
}

// ServerState holds the server state.
type ServerState struct {
	opts                    *ServerOptions            // Options passed to the constructor.
	mutex                   sync.Mutex                // Mutex for changing opts.Config.
	clientIds               StringSet                 // The list of clients we know and which take part in master election.
	clientChannels          ChannelMap                // Channels we use to communicate with client websocket goroutines.
	notificationChannels    ChannelSet                // Channels we use to communicate with notifier websockets goroutines.
	unknownClientIds        StringList                // List of clients we have seen, but don't know.
	clientsLastSeen         TimeSet                   // For any client we have seen, the time when we've last seen him.
	wsChannel               chan *WsMsg               // Channel used by websocket go routines to send messages to dispatcher go routine.
	upgrader                websocket.Upgrader        // Upgrader to use for turning a http connection into a webscoket connection.
	timerChannel            chan string               // Channel used to send an abort message (containing the name of failoverset) to the dispatcher go routine.
	waitGroup               sync.WaitGroup            // Used to organize the shutdown process.
	configChanges           chan consul.Env           // Environment changes from consul arrive on this channel.
	failoverConfidenceLevel float64                   // Failover confidence level, normalized to the interval [0,1.0]
	systemNames             StringList                // All system names. Firste on is used for saving server state.
	failovers               map[string]*FailoverState // Maps system name to failover state.
	cmdChannel              chan command              // Channel for messages to perform state access/changing in the dispatcher thread, passed as closures.
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

var (
	processed     int64
	wsConnections int64
)

// MsgBody facilitates JSON conversion for messages sent btween client and server.
type MsgBody struct {
	System string `json:"system,omitempty"`
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

type command struct {
	closure func()
	reply   chan struct{}
}

// Evaluate sends a command (as a closure) to the dispatcher thread and waits for completion.
func (s *ServerState) Evaluate(closure func()) {
	replyChannel := make(chan struct{}, 1)
	s.cmdChannel <- command{closure: closure, reply: replyChannel}
	<-replyChannel
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

func (s *ServerState) determineFailoverConfidenceLevel() {
	config := s.GetConfig()
	level, err := strconv.Atoi(config.ConfidenceLevel)
	if err != nil {
		level = 100
	} else if level < 0 {
		level = 0
	} else if level > 100 {
		level = 100
	}
	s.failoverConfidenceLevel = float64(level) / 100.0
}

// FailoverStatus
type FailoverStatus struct {
	SystemName             string   `json:"system_name"`
	ConfiguredRedisServers []string `json:"configured_redis_servers"`
	RedisMaster            string   `json:"redis_master"`
	RedisMasterAvailable   bool     `json:"redis_master_available"`
	RedisSlavesAvailable   []string `json:"redis_slaves_available"`
	SwitchInProgress       bool     `json:"switch_in_progress"`
	GCInfo                 *GCInfo  `json:"lastgc"`
}

// ServerStatus is used to faciliate JSON conversion of parts of the server state.
type ServerStatus struct {
	BeetleVersion        string           `json:"beetle_version"`
	ConfiguredClientIds  []string         `json:"configured_client_ids"`
	UnknownClientIds     []string         `json:"unknown_client_ids"`
	UnresponsiveClients  []string         `json:"unresponsive_clients"`
	UnseenClientIds      []string         `json:"unseen_client_ids"`
	Systems              []FailoverStatus `json:"redis_systems"`
	NotificationChannels int              `json:"notification_channels"`
}

// TextMessage template for error pages with automatic redirects
type TextMessage struct {
	TextMessage string
	Class       string
}

func (s *ServerStatus) GetFailoverStatus(system string) *FailoverStatus {
	for _, fs := range s.Systems {
		if fs.SystemName == system {
			return &fs
		}
	}
	return nil
}

// GetStatus creates a ServerStatus from the current server state.
func (s *ServerState) GetStatus() *ServerStatus {
	failoverStats := []FailoverStatus{}

	var keys []string
	for k := range s.failovers {
		keys = append(keys, k)
	}

	sort.Strings(keys)

	for _, system := range keys {
		rs := s.failovers[system]
		failoverStats = append(failoverStats, FailoverStatus{
			SystemName:             system,
			ConfiguredRedisServers: rs.redis.instances.Servers(),
			RedisMaster:            rs.currentMaster.server,
			RedisMasterAvailable:   rs.MasterIsAvailable(),
			RedisSlavesAvailable:   rs.redis.Slaves().Servers(),
			SwitchInProgress:       rs.WatcherPaused(),
			GCInfo:                 rs.gcInfo,
		})
	}

	return &ServerStatus{
		BeetleVersion:        BEETLE_VERSION,
		ConfiguredClientIds:  s.clientIds.Keys(),
		UnknownClientIds:     s.UnknownClientIds(),
		UnresponsiveClients:  s.UnresponsiveClients(),
		UnseenClientIds:      s.UnseenClientIds(),
		Systems:              failoverStats,
		NotificationChannels: len(s.notificationChannels),
	}
}

// GetStatusFromDispatcher retrieves the status from the dispatcher thread.
func (s *ServerState) GetStatusFromDispatcher() *ServerStatus {
	var res *ServerStatus
	s.Evaluate(func() {
		res = s.GetStatus()
	})
	return res
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

func (s *ServerState) dispatcher() {
	ticker := time.NewTicker(1 * time.Second)
	for !interrupted {
		select {
		case cmd := <-s.cmdChannel:
			cmd.closure()
			cmd.reply <- struct{}{}
		case msg := <-s.wsChannel:
			s.handleWebSocketMsg(msg)
		case system := <-s.timerChannel:
			fs := s.failovers[system]
			fs.CancelInvalidation()
		case <-ticker.C:
			for _, fs := range s.failovers {
				fs.watchTick = (fs.watchTick + 1) % s.GetConfig().RedisMasterRetryInterval
				if fs.watchTick == 0 {
					fs.CheckRedisAvailability()
					s.ForgetOldUnknownClientIds()
					s.ForgetOldLastSeenEntries()
				}
			}
		case env := <-s.configChanges:
			newconfig := buildConfig(env)
			s.SetConfig(newconfig)
			s.determineFailoverConfidenceLevel()
			s.updateClientIds()
			s.updateFailoverSets()
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

func (s *ServerState) updateClientIds() {
	s.clientIds = make(StringSet)
	for _, id := range strings.Split(s.GetConfig().ClientIds, ",") {
		if id != "" {
			s.clientIds.Add(id)
			s.unknownClientIds.Remove(id)
		}
	}
}

// NewServerState creates partially initialized ServerState.
func NewServerState(o ServerOptions) *ServerState {
	s := &ServerState{clientChannels: make(ChannelMap), notificationChannels: make(ChannelSet)}
	s.opts = &o
	s.determineFailoverConfidenceLevel()
	s.upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(r *http.Request) bool { return true },
	}
	s.wsChannel = make(chan *WsMsg, 10000)
	s.cmdChannel = make(chan command, 1000)
	s.unknownClientIds = make(StringList, 0)
	s.updateClientIds()
	s.clientsLastSeen = make(TimeSet)
	s.failovers = make(map[string]*FailoverState)
	s.systemNames = make(StringList, 0)
	s.updateFailoverSets()
	return s
}

func (s *ServerState) updateFailoverSets() {
	failovers := s.GetConfig().FailoverSets()
	// delete obsolete failover sets
	newSystemNames := failovers.SystemNames()
	knownSystemNames := s.systemNames
	for _, known := range knownSystemNames {
		if !newSystemNames.Include(known) {
			delete(s.failovers, known)
		}
	}
	s.systemNames = newSystemNames
	// add new failoversets and update already existing ones
	for _, fs := range failovers {
		existing := s.failovers[fs.name]
		if existing != nil {
			if existing.redis.servers != fs.spec {
				existing.redis = NewRedisServerInfo(fs.spec)
				existing.redis.Refresh()
			}
			continue
		}
		initalTokenInt := int(time.Now().UnixNano() / 1000000) // millisecond resolution
		newFailoverState := &FailoverState{
			server:                       s,
			system:                       fs.name,
			currentTokenInt:              initalTokenInt,
			currentToken:                 strconv.Itoa(initalTokenInt),
			redis:                        NewRedisServerInfo(fs.spec),
			clientPongIdsReceived:        make(StringSet),
			clientInvalidatedIdsReceived: make(StringSet),
		}
		s.failovers[fs.name] = newFailoverState
		newFailoverState.StartWatcher()
	}
}

// SaveState stores some aspects of the server state to the current redis master
// to avoid re-sending notifications on restart. As of now, the state only
// consists of the last seen info. It uses the redis master of the first
// failover set.
func (s *ServerState) SaveState() {
	fs := s.failovers[s.systemNames[0]]
	if fs.currentMaster == nil {
		logError("could not save state because no redis master is available")
		return
	}
	lastSeen := make([]string, 0)
	for id, t := range s.clientsLastSeen {
		lastSeen = append(lastSeen, fmt.Sprintf("%s:%d", id, t.UnixNano()))
	}
	lastSeenStr := strings.Join(lastSeen, ",")
	_, err := fs.currentMaster.redis.Set("beetle:clients-last-seen", lastSeenStr, 0).Result()
	if err != nil {
		logError("could not save clients last seen info to redis")
	}
	logDebug("saved last seen info to redis: %s", lastSeenStr)
}

// LoadState loads previously saved state from current redis master.
func (s *ServerState) LoadState() {
	if len(s.systemNames) == 0 {
		return
	}
	fs := s.failovers[s.systemNames[0]]
	if fs.currentMaster == nil {
		logError("could not restore state because we have no redis master")
		return
	}
	v, err := fs.currentMaster.redis.Get("beetle:clients-last-seen").Result()
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

func (s *ServerState) setupClientHandler(webSocketPort int) *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.dispatchRequest)
	logInfo("Starting web socket server on port %d", webSocketPort)
	webSocketSpec := ":" + strconv.Itoa(webSocketPort)
	return &http.Server{
		Addr:    webSocketSpec,
		Handler: mux,
	}
}

func (s *ServerState) runClientHandler(srv *http.Server) {
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logError("starting websocket server failed")
	}
}

func (s *ServerState) shutdownClientHandler(srv *http.Server, timeout time.Duration) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	err := srv.Shutdown(ctx)
	if err != nil {
		logError("web server shutdown failed: %+v", err)
	} else {
		logInfo("web server shutdown successful")
	}
}

func (s *ServerState) serveNotifications(w http.ResponseWriter, r *http.Request) {
	logDebug("received notification request")
	ws, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		if _, ok := err.(websocket.HandshakeError); !ok {
			logError("serveNotifications: %s", err)
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
			err := ws.WriteMessage(websocket.TextMessage, []byte(data))
			if err != nil {
				logError("Could not send notification: %s", err)
				return
			}
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
			logError("serveWS: %s", err)
		}
		return
	}
	defer ws.Close()
	defer (func() {
		atomic.AddInt64(&wsConnections, -1)
	})()
	s.wsReader(ws)
}

func (s *ServerState) serveGCStats(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html")
	keys, ok := r.URL.Query()["system"]
	if !ok || len(keys[0]) < 1 {
		logError("Url parameter 'system' is missing")
		w.WriteHeader(400)
		return
	}
	system := keys[0]
	tmpl, err := template.New("gcstats.html").Parse(gcStatsTemplate)
	if err != nil {
		w.WriteHeader(500)
		return
	}
	status := s.GetStatusFromDispatcher()
	fs := status.GetFailoverStatus(system)
	if fs == nil {
		w.WriteHeader(404)
		return
	}
	err = tmpl.Execute(w, fs.GCInfo)
	if err != nil {
		logError("template execution failed: %s", err)
	}
}

func (s *ServerState) dispatchRequest(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/", "/.html":
		w.Header().Set("Content-Type", "text/html")
		tmpl, err := template.New("index.html").Parse(htmlTemplate)
		if err != nil {
			w.WriteHeader(500)
			return
		}
		err = tmpl.Execute(w, s.GetStatusFromDispatcher())
		if err != nil {
			logError("template execution failed: %s", err)
		}
	case "/.json":
		w.Header().Set("Content-Type", "application/json")
		b, err := json.Marshal(s.GetStatusFromDispatcher())
		if err != nil {
			w.WriteHeader(500)
			return
		}
		fmt.Fprintf(w, "%s", string(b))
	case "/.txt":
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "Not yet implemented")
	case "/initiate_master_switch":
		w.Header().Set("Content-Type", "text/html")
		s.initiateMasterSwitch(w, r)
	case "/brokers":
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "[]")
	case "/configuration":
		s.serveWs(w, r)
	case "/notifications":
		s.serveNotifications(w, r)
	case "/gcstats":
		s.serveGCStats(w, r)
	default:
		http.NotFound(w, r)
	}
}

func renderErrorTemplate(w http.ResponseWriter, code int, msg string) {
	tmpl, err := template.New("message.html").Parse(messageTemplate)
	if err != nil {
		w.WriteHeader(500)
		return
	}
	w.WriteHeader(code)
	class := "info"
	if code >= 400 {
		class = "error"
	}
	err = tmpl.Execute(w, TextMessage{TextMessage: msg, Class: class})
	if err != nil {
		logError("template execution failed: %s", err)
		return
	}
}

func (s *ServerState) initiateMasterSwitch(w http.ResponseWriter, r *http.Request) {
	system := r.URL.Query().Get("system_name")
	if system == "" {
		renderErrorTemplate(w, 400, "Missing parameter: system_name")
		return
	}
	fs := s.failovers[system]
	if fs == nil {
		renderErrorTemplate(w, 400, fmt.Sprintf("Master switch not possible for unknown system: '%s'", system))
		return
	}
	var initiated bool
	s.Evaluate(func() { initiated = fs.InitiateMasterSwitch() })
	if initiated {
		renderErrorTemplate(w, 201, "Master switch initiated")
	} else {
		renderErrorTemplate(w, 200, "No master switch necessary")
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
	defer func() {
		err := ws.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(1000, "good bye"))
		if err != nil {
			logError("writing websocket close failed: %s", err)
		}
	}()
	for !interrupted {
		select {
		case data, ok := <-inputFromDispatcher:
			if !ok {
				logInfo("Closed channel for %s", clientID)
				return
			}
			err := ws.WriteMessage(websocket.TextMessage, []byte(data))
			if err != nil {
				logError("Could not send message on websocket")
				return
			}
		case <-time.After(100 * time.Millisecond):
			// give the outer loop a chance to detect interrupts
		}
	}
}

// Initialize completes the state initialization by checking redis connectivity
// and loading saved state.
func (s *ServerState) Initialize() {
	config := s.GetConfig()
	websocket.DefaultDialer.HandshakeTimeout = time.Duration(config.DialTimeout) * time.Second
	VerifyMasterFileString(config.RedisMasterFile)
	var masters map[string]string
	if MasterFileExists(config.RedisMasterFile) {
		masters = RedisMastersFromMasterFile(config.RedisMasterFile)
	} else if s.opts.ConsulClient != nil {
		kv, err := s.opts.ConsulClient.GetState()
		if err != nil {
			logError("Could not load state from consul: %s", err)
		}
		masters = UnmarshalMasterFileContent(kv["redis_master_file_content"])
	}
	for system, fs := range s.failovers {
		fs.CheckRedisConfiguration()
		fs.redis.Refresh()
		fs.DetermineInitialMaster(masters)
		if fs.currentMaster == nil {
			logError("Could not determine initial master for system: %s", system)
			os.Exit(1)
		}
	}
	s.UpdateMasterFile()
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
	fs := s.failovers[msg.System]
	if !fs.RedeemToken(msg.Token) {
		return
	}
	fs.clientPongIdsReceived.Add(msg.Id)
	level, enough := fs.ReceivedEnoughClientPongIds()
	if fs.pinging && enough {
		logInfo("Received a sufficient number of pong ids!. Confidence level: %f.", level)
		fs.StopPinging()
		fs.InvalidateCurrentMaster()
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
	fs := s.failovers[msg.System]
	fs.clientInvalidatedIdsReceived.Add(msg.Id)
	level, enough := fs.ReceivedEnoughClientInvalidatedIds()
	if fs.invalidating && enough {
		logInfo("Received a sufficient number of client invalidated ids! Confidence level: %f.", level)
		fs.StopInvalidating()
		fs.SwitchMaster()
	}
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

// UpdateMasterFile writes the known masters information to the redis master file.
func (s *ServerState) UpdateMasterFile() {
	path := s.GetConfig().RedisMasterFile
	systems := make(map[string]string, 0)
	for _, fs := range s.failovers {
		if fs.currentMaster == nil {
			systems[fs.system] = ""
		} else {
			systems[fs.system] = fs.currentMaster.server
		}
	}
	content := MarshalMasterFileContent(systems)
	WriteRedisMasterFile(path, content)
	if s.opts.ConsulClient != nil {
		err := s.opts.ConsulClient.UpdateState("redis_master_file_content", content)
		if err != nil {
			logError("could not update consul state: %s", err)
		}
	}
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
