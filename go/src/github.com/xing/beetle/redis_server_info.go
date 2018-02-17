package main

import (
	"regexp"

	//	"github.com/davecgh/go-spew/spew"
	"gopkg.in/redis.v5"
)

// RedisShims is a slice of RedisShim objects.
type RedisShims []*RedisShim

// Include checks whether a given slice of Redis shimes contains a given redis
// server string.
func (shims RedisShims) Include(r *RedisShim) bool {
	for _, x := range shims {
		if x.server == r.server {
			return true
		}
	}
	return false
}

// Servers returns a slice od server strings (host:port format).
func (shims RedisShims) Servers() []string {
	servers := make([]string, 0)
	for _, x := range shims {
		servers = append(servers, x.server)
	}
	return servers
}

// RedisServerInfo contans a list slice of RedisShim objects and a lookup index
// on server strings (host:port format).
type RedisServerInfo struct {
	instances  RedisShims
	serverInfo map[string]RedisShims
}

// NewRedisServerInfo creates a new RedisServerInfo from a comma separated list
// of servers (host:port format).
func NewRedisServerInfo(servers string) *RedisServerInfo {
	si := &RedisServerInfo{}
	si.instances = make(RedisShims, 0)
	if servers != "" {
		serverList := regexp.MustCompile(" *, *").Split(servers, -1)
		for _, s := range serverList {
			logInfo("adding redis server: %s", s)
			si.instances = append(si.instances, NewRedisShim(s))
		}
	}
	si.Reset()
	return si
}

// NumServers returns the number of servers.
func (si *RedisServerInfo) NumServers() int {
	return len(si.instances)
}

// Reset clears all info.
func (si *RedisServerInfo) Reset() {
	m := make(map[string]RedisShims)
	m[MASTER] = make(RedisShims, 0)
	m[SLAVE] = make(RedisShims, 0)
	m[UNKNOWN] = make(RedisShims, 0)
	si.serverInfo = m
}

// Refresh contacts all redis servers and dtermines their current role.
func (si *RedisServerInfo) Refresh() {
	logDebug("refreshing server info")
	si.Reset()
	for _, ri := range si.instances {
		role := ri.Role()
		logDebug("determined %s to be a '%s'", ri.server, role)
		si.serverInfo[role] = append(si.serverInfo[role], ri)
	}
	// spew.Dump(si)
}

// Find returns the redis client instance for a given server specification.
func (si *RedisServerInfo) Find(server string) *redis.Client {
	for _, r := range si.instances {
		if r.server == server {
			return r.redis
		}
	}
	return nil
}

// Masters returns all shims with role 'master'.
func (si *RedisServerInfo) Masters() RedisShims {
	return si.serverInfo[MASTER]
}

// Slaves returns all shims with role 'slave'.
func (si *RedisServerInfo) Slaves() RedisShims {
	return si.serverInfo[SLAVE]
}

// Unknowns returns all shims with role 'unknown'.
func (si *RedisServerInfo) Unknowns() RedisShims {
	return si.serverInfo[UNKNOWN]
}

// SlavesOf returns all shims for servers which are salves of the given server.
func (si *RedisServerInfo) SlavesOf(master *RedisShim) RedisShims {
	slaves := make(RedisShims, 0)
	for _, s := range si.Slaves() {
		if s.IsSlaveOf(master.host, master.port) {
			slaves = append(slaves, s)
		}
	}
	return slaves
}

// AutoDetectMaster returns the current master, if it is reachable.
func (si *RedisServerInfo) AutoDetectMaster() *RedisShim {
	if !si.MasterAndSlavesReachable() {
		return nil
	}
	return si.Masters()[0]
}

// MasterAndSlavesReachable checks whether the master and all its slaves are
// reachable.
func (si *RedisServerInfo) MasterAndSlavesReachable() bool {
	return len(si.Masters()) == 1 && len(si.Slaves()) == len(si.instances)-1
}
