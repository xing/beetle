package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strconv"
	"time"
)

// FailoverState holds information relevant to each failover set.
type FailoverState struct {
	redis                        *RedisServerInfo // Cached state of watched redis instances. Refreshed every RedisMasterRetryInterval seconds.
	currentMaster                *RedisShim       // Current redis master.
	currentTokenInt              int              // Token to identify election rounds.
	currentToken                 string           // String representation of current token.
	pinging                      bool             // Whether or not we're waiting for pings
	invalidating                 bool             // Whether or not we're waiting for invalidations.
	clientPongIdsReceived        StringSet        // During a pong phase, the set of clients which have answered.
	clientInvalidatedIdsReceived StringSet        // During the invalidation phase, the set of clients which have answered.
	watching                     bool             // Whether we're currently watching a redis master (false during election process).
	watchTick                    int              // One second tick counter which gets reset every RedisMasterRetryInterval seconds.
	invalidateTimer              *time.Timer      // Timer used to abort waiting for answers from clients (invalidate/invalidated).
	availabilityTimer            *time.Timer      // Timer used to abort waiting for answers from clients (ping/pong).
	retries                      int              // Count down for checking a master to come back after it has become unreachable.
	system                       string           // The name of the failover set.
	server                       *ServerState     // Backpointer to embedding server.
	gcInfo                       *GCInfo          // Information on last garbage collection.
}

// GetConfig returns the server state in a thread safe manner.
func (s *FailoverState) GetConfig() *Config {
	return s.server.GetConfig()
}

// ClientTimeout returns the client timeout as a time.Duration.
func (s *FailoverState) ClientTimeout() time.Duration {
	return s.server.ClientTimeout()
}

// SetGCInfo retrieves info about the last garbage collection from the urrent master and remembers it.
func (s *FailoverState) SetGCInfo() {
	if s.currentMaster == nil {
		return
	}
	data, err := s.currentMaster.redis.Get("beetle:lastgc").Result()
	if err != nil {
		logInfo("could not retrieve last GC info for system '%s': %s", s.system, err)
		return
	}
	var info GCInfo
	err = json.Unmarshal([]byte(data), &info)
	if err != nil {
		logInfo("could not unmarshal last GC info for system '%s': %s", s.system, err)
		return
	}
	s.gcInfo = &info
}

// SendToWebSockets sends a message to all registered clients channels.
func (s *FailoverState) SendToWebSockets(msg *MsgBody) (err error) {
	return s.server.SendToWebSockets(msg)
}

// SendNotification sends a notification on all registered notification channels.
func (s *FailoverState) SendNotification(text string) (err error) {
	return s.server.SendNotification(text)
}

// StopPinging changes the current state to 'not pinging' and cancels the
// inavailability timer if one is active.
func (s *FailoverState) StopPinging() {
	s.pinging = false
	if s.availabilityTimer != nil {
		s.availabilityTimer.Stop()
		s.availabilityTimer = nil
	}
}

// StopInvalidating changes the state to 'not invalidating' and cancels the
// invalidation timer if one is active.
func (s *FailoverState) StopInvalidating() {
	s.invalidating = false
	if s.invalidateTimer != nil {
		s.invalidateTimer.Stop()
		s.invalidateTimer = nil
	}
}

// MasterUnavailable pauses the redis watcher, sends a nofication that the redis
// master has become unavailable and starts the voting process on whether to
// switch or not. If no client ids have been configured, it switches the master
// immediately.
func (s *FailoverState) MasterUnavailable() {
	s.PauseWatcher()
	msg := fmt.Sprintf("Redis master '%s' not available", s.currentMaster.server)
	logWarn(msg)
	s.SendNotification(msg)
	if len(s.server.clientIds) == 0 {
		s.SwitchMaster()
	} else {
		s.StartInvalidation()
	}
}

// MasterAvailable sends current master info to all connected clients and
// reconfigures remaining redis servers as slaves of the (new) master.
func (s *FailoverState) MasterAvailable() {
	s.PublishMaster(s.currentMaster.server)
	s.ConfigureSlaves(s.currentMaster)
	s.server.SaveState()
}

// MasterIsAvailable uses the cached redis information to determine whether the
// currently configured master is in fact available.
func (s *FailoverState) MasterIsAvailable() bool {
	logDebug("Checking master availability. currentMaster: '%+v'", s.currentMaster)
	return s.redis.Masters().Include(s.currentMaster)
}

// AvailableSlaves retrieves the list of slaves from the cached redis
// information.
func (s *FailoverState) AvailableSlaves() RedisShims {
	return s.redis.Slaves()
}

// InitiateMasterSwitch refreshes the cached redis information and starts a vote
// on a new redis server, unless there is already a vote in progress or the
// currently configured redis master is available.
func (s *FailoverState) InitiateMasterSwitch() bool {
	s.redis.Refresh()
	available, switchInProgress := s.MasterIsAvailable(), s.WatcherPaused()
	logInfo("Initiating master switch: already in progress = %v", switchInProgress)
	if !(available || switchInProgress) {
		s.MasterUnavailable()
	}
	return !available || switchInProgress
}

// CheckRedisConfiguration checks whether we have at leats two redis servers.
func (s *FailoverState) CheckRedisConfiguration() {
	if s.redis.NumServers() < 2 {
		logError("Redis failover needs at least two redis servers")
		os.Exit(1)
	}
}

// DetermineInitialMaster either uses information from the master file on disk
// (passed in as a map) or tries to auto detect inital redis masters and writes
// the updated file to disk. If no master can be determined, the main server
// loop will start a vote later on.
func (s *FailoverState) DetermineInitialMaster(mastersFromFile map[string]string) {
	if server := mastersFromFile[s.system]; server != "" {
		s.currentMaster = NewRedisShim(server)
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
	}
	s.SetGCInfo()
}

// DetermineNewMaster uses the cached redis information to either select a new
// master from slaves of the current master or simply returns the current
// master, if it can still be reached.
func (s *FailoverState) DetermineNewMaster() *RedisShim {
	if s.redis.Unknowns().Include(s.currentMaster) {
		slaves := s.redis.SlavesOf(s.currentMaster)
		if len(slaves) == 0 {
			return nil
		}
		return slaves[0]
	}
	return s.currentMaster
}

// RedeemToken checks whether the given token is valid for the current vote.
func (s *FailoverState) RedeemToken(token string) bool {
	if token == s.currentToken {
		return true
	}
	logInfo("Ignored message (token was '%s', but expected '%s'", token, s.currentToken)
	return false
}

// GenerateNewToken generates a new token by incrementing a counter maintained
// in the server state.
func (s *FailoverState) GenerateNewToken() {
	s.currentTokenInt++
	s.currentToken = strconv.Itoa(s.currentTokenInt)
}

// StartInvalidation resets the state information used to keep track of the an
// ongoing vote and starts a new vote.
func (s *FailoverState) StartInvalidation() {
	s.clientPongIdsReceived = make(StringSet)
	s.clientInvalidatedIdsReceived = make(StringSet)
	s.pinging = true
	s.invalidating = false
	s.CheckEnoughClientsAvailable()
}

// CheckEnoughClientsAvailable sends a PING message to all connected clients.
func (s *FailoverState) CheckEnoughClientsAvailable() {
	s.GenerateNewToken()
	logInfo("Sending ping messages with token '%s'", s.currentToken)
	msg := &MsgBody{System: s.system, Name: PING, Token: s.currentToken}
	s.SendToWebSockets(msg)
	s.availabilityTimer = time.AfterFunc(s.ClientTimeout(), func() {
		s.availabilityTimer = nil
		s.server.timerChannel <- s.system
	})
}

// InvalidateCurrentMaster sends the INVALIDATE message to all connected
// clients.
func (s *FailoverState) InvalidateCurrentMaster() {
	s.GenerateNewToken()
	s.invalidating = true
	logInfo("Sending invalidate messages with token '%s'", s.currentToken)
	msg := &MsgBody{System: s.system, Name: INVALIDATE, Token: s.currentToken}
	s.SendToWebSockets(msg)
	s.invalidateTimer = time.AfterFunc(s.ClientTimeout(), func() {
		s.invalidateTimer = nil
		s.server.timerChannel <- s.system
	})
}

// CancelInvalidation generates a new token to the next vote and unpauses the
// watcher.
func (s *FailoverState) CancelInvalidation() {
	s.pinging = false
	s.invalidating = false
	s.GenerateNewToken()
	s.StartWatcher()
}

// ReceivedEnoughClientPongIds checks whether a sufficient number of client's have
// answered the PING message by sending a PONG.
func (s *FailoverState) ReceivedEnoughClientPongIds() (float64, bool) {
	received := s.clientPongIdsReceived.Intersect(s.server.clientIds)
	level := float64(len(received)) / float64(len(s.server.clientIds))
	return level, level >= s.server.failoverConfidenceLevel
}

// ReceivedEnoughClientInvalidatedIds checks whether all client's have answered the
// INVALIDATE message by sending a CLIENT_INVALIDATED message back.
func (s *FailoverState) ReceivedEnoughClientInvalidatedIds() (float64, bool) {
	received := s.clientInvalidatedIdsReceived.Intersect(s.server.clientIds)
	level := float64(len(received)) / float64(len(s.server.clientIds))
	return level, level >= s.server.failoverConfidenceLevel
}

// SwitchMaster is called after a successfully completed vote and performs a
// switch to a new master, if possible. If no new master can be determined, it
// starts watching the old master again. In either case, a notification message
// is sent out.
func (s *FailoverState) SwitchMaster() {
	newMaster := s.DetermineNewMaster()
	if newMaster != nil {
		msg := fmt.Sprintf("Setting redis master to '%s' (was '%s')", newMaster.server, s.currentMaster.server)
		logWarn(msg)
		s.SendNotification(msg)
		newMaster.MakeMaster()
		s.currentMaster = newMaster
		s.server.UpdateMasterFile()
	} else {
		msg := fmt.Sprintf("Redis master could not be switched, no slave available to become new master, promoting old master")
		logError(msg)
		s.SendNotification(msg)
	}
	s.PublishMaster(s.currentMaster.server)
	s.StartWatcher()
}

// PublishMaster sends the RECONFIGURE message to all connected clients.
func (s *FailoverState) PublishMaster(server string) {
	logInfo("Sending reconfigure message with server '%s' and token: '%s'", server, s.currentToken)
	msg := &MsgBody{System: s.system, Name: RECONFIGURE, Server: server, Token: s.currentToken}
	s.SendToWebSockets(msg)
}

// ConfigureSlaves turns all available servers into slaves of the current master.
func (s *FailoverState) ConfigureSlaves(master *RedisShim) {
	for _, r := range s.redis.MastersAndSlaves() {
		if r.server != master.server {
			r.redis.SlaveOf(master.host, strconv.Itoa(master.port))
		}
	}
}

// WatcherPaused checks whether the redis watcher has been paused.
func (s *FailoverState) WatcherPaused() bool {
	return !s.watching
}

// StartWatcher starts watching the redis server status.
func (s *FailoverState) StartWatcher() {
	if s.WatcherPaused() {
		s.watchTick = 0
		s.watching = true
		logInfo("Starting watching redis servers every %d seconds", s.GetConfig().RedisMasterRetryInterval)
	}
}

// PauseWatcher starts watching the redis server status.
func (s *FailoverState) PauseWatcher() {
	if !s.WatcherPaused() {
		s.watching = false
		logInfo("Paused checking availability of redis servers")
	}
}

// CheckRedisAvailability uses
func (s *FailoverState) CheckRedisAvailability() {
	s.redis.Refresh()
	if s.MasterIsAvailable() {
		s.retries = 0
		if s.pinging {
			s.StopPinging()
			logInfo("Redis master came online while pinging")
		}
		if s.invalidating {
			s.StopInvalidating()
			logInfo("Redis master came online while invalidating")
		}
		s.StartWatcher()
		s.MasterAvailable()
		s.SetGCInfo()
	} else {
		retriesLeft := s.GetConfig().RedisMasterRetries - (s.retries + 1)
		logWarn("Redis master not available! (Retries left: %d)", retriesLeft)
		s.retries++
		if s.retries >= s.GetConfig().RedisMasterRetries {
			// prevent starting a new master switch while one is running
			s.retries = math.MinInt32
			s.MasterUnavailable()
		}
	}
}
