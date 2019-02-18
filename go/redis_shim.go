package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gopkg.in/redis.v5"
)

// Some string constants.
const (
	MASTER  = "master"
	SLAVE   = "slave"
	UNKNOWN = "unknown"
)

// RedisShim contains info about server name and port and a pointer to the
// underlying redis client.
type RedisShim struct {
	redis  *redis.Client
	server string
	host   string
	port   int
}

// NewRedisShim creates a new shim from a server:port string, where the port
// part is optional.
func NewRedisShim(server string) *RedisShim {
	ri := new(RedisShim)
	ri.server = server
	parts := strings.Split(server, ":")
	ri.host = parts[0]
	ri.port, _ = strconv.Atoi(parts[1])
	ri.redis = redisInstanceFromServerString(server)
	return ri
}

func redisInstanceFromServerString(server string) *redis.Client {
	return redis.NewClient(&redis.Options{Addr: server})
}

func dumpMap(m map[string]string) {
	fmt.Printf("MAP[\n")
	for k, v := range m {
		fmt.Printf("'%s' : '%s'\n", k, v)
	}
	fmt.Printf("]MAP\n")
}

// Info runs the INFO command on the redis server and returns a map of strings.
func (ri *RedisShim) Info() (m map[string]string) {
	m = make(map[string]string)
	t := time.Now()
	cmd := ri.redis.Info("Replication")
	s, err := cmd.Result()
	if err != nil {
		logError("could not obtain redis info from %s: %s", ri.server, err)
		return
	}
	logInfo("obtaining redis info from %s took %s", ri.server, time.Since(t))
	re := regexp.MustCompile("([^:]+):(.*)")
	ss := strings.Split(s, "\n")
	for _, x := range ss {
		match := re.FindStringSubmatch(x)
		if len(match) == 3 {
			k, v := match[1], match[2]
			// there's junk at the end of v
			m[k] = v[0 : len(v)-1]
		}
	}
	return
}

// Role returns the role of the redis server ('master' or 'söave'), or 'unknown'
// if the server cannot be reached.
func (ri *RedisShim) Role() string {
	info := ri.Info()
	if len(info) == 0 {
		return UNKNOWN
	}
	return info["role"]
}

// IsMaster checks whether the redis server is a master.
func (ri *RedisShim) IsMaster() bool {
	return ri.Role() == MASTER
}

// IsSlave checks whether the redis server is a slave.
func (ri *RedisShim) IsSlave() bool {
	return ri.Role() == SLAVE
}

// IsAvailable checks whether the server is available.
func (ri *RedisShim) IsAvailable() bool {
	t := time.Now()
	cmd := ri.redis.Ping()
	_, err := cmd.Result()
	if err != nil {
		logError("pinging server %s failed: %s", ri.server, err)
		return false
	}
	logInfo("pinging server %s took %t", ri.server, time.Since(t))
	return true
}

// MakeMaster sends SALVEOF no one to the redis server.
func (ri *RedisShim) MakeMaster() error {
	t := time.Now()
	cmd := ri.redis.SlaveOf("no", "one")
	_, err := cmd.Result()
	if err != nil {
		logError("could not make %s a slave of no one: %s", ri.server, err)
	} else {
		logInfo("making %s a slave of no one took %s", ri.server, time.Since(t))
	}
	return err
}

// IsSlaveOf checks whether the redis server is a slave of some other server.
func (ri *RedisShim) IsSlaveOf(host string, port int) bool {
	info := ri.Info()
	return info["role"] == SLAVE && info["master_host"] == host && info["master_port"] == strconv.Itoa(port)
}

// RedisMakeSlave makes the redis server slave of some other server.
func (ri *RedisShim) RedisMakeSlave(host string, port int) error {
	t := time.Now()
	cmd := ri.redis.SlaveOf(host, strconv.Itoa(port))
	_, err := cmd.Result()
	if err != nil {
		logError("could not make %s a slave of %s:%d: %s", ri.server, host, port, err)
	} else {
		logInfo("making %s a slave of %s:%d took %s", ri.server, host, port, time.Since(t))
	}
	return err
}
