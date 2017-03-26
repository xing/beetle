package main

import (
	"regexp"

	//	"github.com/davecgh/go-spew/spew"
	"gopkg.in/redis.v5"
)

type RedisShims []*RedisShim

func (shims RedisShims) Include(r *RedisShim) bool {
	for _, x := range shims {
		if x.server == r.server {
			return true
		}
	}
	return false
}

func (shims RedisShims) Servers() []string {
	servers := make([]string, 0)
	for _, x := range shims {
		servers = append(servers, x.server)
	}
	return servers
}

type RedisServerInfo struct {
	instances  RedisShims
	serverInfo map[string]RedisShims
}

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

func (si *RedisServerInfo) NumServers() int {
	return len(si.instances)
}

func (si *RedisServerInfo) Reset() {
	m := make(map[string]RedisShims)
	m[MASTER] = make(RedisShims, 0)
	m[SLAVE] = make(RedisShims, 0)
	m[UNKNOWN] = make(RedisShims, 0)
	si.serverInfo = m
}

func (si *RedisServerInfo) Refresh() {
	logInfo("refreshing server info")
	si.Reset()
	for _, ri := range si.instances {
		role := ri.Role()
		logInfo("determined %s to be a '%s'", ri.server, role)
		si.serverInfo[role] = append(si.serverInfo[role], ri)
	}
	// spew.Dump(si)
}

func (si *RedisServerInfo) Find(server string) *redis.Client {
	for _, r := range si.instances {
		if r.server == server {
			return r.redis
		}
	}
	return nil
}

func (si *RedisServerInfo) Masters() RedisShims {
	return si.serverInfo[MASTER]
}

func (si *RedisServerInfo) Slaves() RedisShims {
	return si.serverInfo[SLAVE]
}

func (si *RedisServerInfo) Unknowns() RedisShims {
	return si.serverInfo[UNKNOWN]
}

func (si *RedisServerInfo) SlavesOf(master *RedisShim) RedisShims {
	slaves := make(RedisShims, 0)
	for _, s := range si.Slaves() {
		if s.IsSlaveOf(master.host, master.port) {
			slaves = append(slaves, s)
		}
	}
	return slaves
}

func (si *RedisServerInfo) AutoDetectMaster() *RedisShim {
	if !si.MasterAndSlavesReachable() {
		return nil
	}
	return si.Masters()[0]
}

func (si *RedisServerInfo) MasterAndSlavesReachable() bool {
	return len(si.Masters()) == 1 && len(si.Slaves()) == len(si.instances)-1
}
