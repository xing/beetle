package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"gopkg.in/redis.v5"
)

const (
	MASTER  = "master"
	SLAVE   = "slave"
	UNKNOWN = "unknown"
)

type RedisShim struct {
	redis  *redis.Client
	server string
	host   string
	port   int
}

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

func (ri *RedisShim) Info() (m map[string]string) {
	m = make(map[string]string)
	cmd := ri.redis.Info("Replication")
	s, err := cmd.Result()
	if err != nil {
		return
	}
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

func (ri *RedisShim) Role() string {
	info := ri.Info()
	if len(info) == 0 {
		return UNKNOWN
	}
	return info["role"]
}

func (ri *RedisShim) IsMaster() bool {
	return ri.Role() == MASTER
}

func (ri *RedisShim) IsSlave() bool {
	return ri.Role() == SLAVE
}

func (ri *RedisShim) IsAvailable() bool {
	cmd := ri.redis.Ping()
	_, err := cmd.Result()
	return err == nil
}

func (ri *RedisShim) MakeMaster() error {
	cmd := ri.redis.SlaveOf("no", "one")
	_, err := cmd.Result()
	return err
}

func (ri *RedisShim) IsSlaveOf(host string, port int) bool {
	info := ri.Info()
	return info["role"] == SLAVE && info["master_host"] == host && info["master_port"] == strconv.Itoa(port)
}

func (ri *RedisShim) RedisMakeSlave(host string, port int) error {
	cmd := ri.redis.SlaveOf(host, strconv.Itoa(port))
	_, err := cmd.Result()
	return err
}
