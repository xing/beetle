package main

import (
	"strconv"
	"strings"

	"github.com/xing/beetle/consul"
	"gopkg.in/yaml.v2"
)

// Config holds externally configurable options.
type Config struct {
	Server                   string `yaml:"redis_configuration_server"`
	Port                     int    `yaml:"redis_configuration_server_port"`
	RedisServers             string `yaml:"redis_servers"`
	ClientIds                string `yaml:"redis_configuration_client_ids"`
	ClientHeartbeat          int    `yaml:"redis_configuration_client_heartbeat"`
	ClientTimeout            int    `yaml:"redis_configuration_client_timeout"`
	RedisMasterRetries       int    `yaml:"redis_configuration_master_retries"`
	RedisMasterRetryInterval int    `yaml:"redis_configuration_master_retry_interval"`
	RedisMasterFile          string `yaml:"redis_server"`
	GcThreshold              int    `yaml:"redis_gc_threshold"`
	GcDatabases              string `yaml:"redis_gc_databases"`
	MailTo                   string `yaml:"mail_to"`
	DialTimeout              int    `yaml:"dial_timeout"`
	ConfidenceLevel          string `yaml:"redis_failover_confidence_level"`
}

// Clone copies a give config.
func (c *Config) Clone() *Config {
	d := *c
	return &d
}

// String converts a Config into its YAML representation.
func (c *Config) String() string {
	yamlBytes, err := yaml.Marshal(c)
	if err != nil {
		return err.Error()
	}
	return string(yamlBytes)
}

// ServerUrl constructs a server URL hostname and port.
func (c *Config) ServerUrl() string {
	return c.Server + ":" + strconv.Itoa(c.Port)
}

// Sanitize replaces newlines by commas. Used to support newlines in consul
// definitions.
func (c *Config) Sanitize() {
	if strings.Contains(c.ClientIds, "\n") {
		c.ClientIds = strings.Replace(c.ClientIds, "\n", ",", -1)
	}
}

//
type FailoverSet struct {
	name string
	spec string
}

// FailoverSets parses the redis server spec and returns a list of pairs of system
// names and comma separated strings of redis server specs (host:port pairs). Examples:
// "a1:5,a2:5" ==> {"system": "a1:5,a2:5" } "primary/a1:5,a2:5\nsecondary/b1:3,b2:3" ==>
// {"primary": "a1:5,a2:5", "secondary": "b1:3,b2:3"}
func (c *Config) FailoverSets() []FailoverSet {
	fs := []FailoverSet{}
	for _, line := range strings.Split(c.RedisServers, "\n") {
		if line == "" {
			continue
		}
		if strings.Contains(line, "/") {
			parts := strings.SplitN(line, "/", 2)
			fs = append(fs, FailoverSet{name: parts[0], spec: parts[1]})
			continue
		}
		fs = append(fs, FailoverSet{name: "system", spec: line})
	}
	return fs
}

// SetDefaults sets default values for all config options. It is called as the
// last step to set up a Config.
func (c *Config) SetDefaults() *Config {
	if c.ClientTimeout == 0 {
		c.ClientTimeout = 10
	}
	if c.ClientHeartbeat == 0 {
		c.ClientHeartbeat = 5
	}
	if c.RedisMasterRetries == 0 {
		c.RedisMasterRetries = 3
	}
	if c.RedisMasterRetryInterval == 0 {
		c.RedisMasterRetryInterval = 10
	}
	if c.Server == "" {
		c.Server = "127.0.0.1"
	}
	if c.Port == 0 {
		c.Port = 9650
	}
	if c.GcThreshold == 0 {
		c.GcThreshold = 3600 // 1 hour
	}
	if c.GcDatabases == "" {
		c.GcDatabases = "4"
	}
	if c.MailTo == "" {
		c.MailTo = "root@localhost"
	}
	if c.RedisMasterFile == "" {
		c.RedisMasterFile = "/etc/beetle/redis-master"
	}
	if c.DialTimeout == 0 {
		c.DialTimeout = 5
	}
	if c.ConfidenceLevel == "" {
		c.ConfidenceLevel = "100"
	}
	c.Sanitize()
	return c
}

// Merge merges two configs c and d. Settings in c have precedence over those in d.
func (c *Config) Merge(d *Config) *Config {
	if d == nil {
		return c
	}
	if c.Server == "" {
		c.Server = d.Server
	}
	if c.Port == 0 {
		c.Port = d.Port
	}
	if c.RedisServers == "" {
		c.RedisServers = d.RedisServers
	}
	if c.ClientIds == "" {
		c.ClientIds = d.ClientIds
	}
	if c.ClientTimeout == 0 {
		c.ClientTimeout = d.ClientTimeout
	}
	if c.ClientHeartbeat == 0 {
		c.ClientHeartbeat = d.ClientHeartbeat
	}
	if c.RedisMasterRetries == 0 {
		c.RedisMasterRetries = d.RedisMasterRetries
	}
	if c.RedisMasterRetryInterval == 0 {
		c.RedisMasterRetryInterval = d.RedisMasterRetryInterval
	}
	if c.RedisMasterFile == "" {
		c.RedisMasterFile = d.RedisMasterFile
	}
	if c.GcThreshold == 0 {
		c.GcThreshold = d.GcThreshold
	}
	if c.GcDatabases == "" {
		c.GcDatabases = d.GcDatabases
	}
	if c.MailTo == "" {
		c.MailTo = d.MailTo
	}
	if c.DialTimeout == 0 {
		c.DialTimeout = d.DialTimeout
	}
	if c.DialTimeout == 0 {
		c.DialTimeout = d.DialTimeout
	}
	if c.ConfidenceLevel == "" {
		c.ConfidenceLevel = d.ConfidenceLevel
	}
	c.Sanitize()
	return c
}

// create a config from a consul Env object.
func configFromConsulEnv(env consul.Env) *Config {
	if env == nil {
		return nil
	}
	var c Config
	if v, ok := env["REDIS_CONFIGURATION_SERVER"]; ok {
		c.Server = v
	}
	if v, ok := env["REDIS_CONFIGURATION_SERVER_PORT"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.Port = d
		}
	}
	if v, ok := env["REDIS_SERVERS"]; ok {
		c.RedisServers = v
	}
	if v, ok := env["REDIS_CONFIGURATION_CLIENT_IDS"]; ok {
		c.ClientIds = v
	}
	if v, ok := env["REDIS_CONFIGURATION_CLIENT_HEARTBEAT"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.ClientHeartbeat = d
		}
	}
	if v, ok := env["REDIS_CONFIGURATION_CLIENT_TIMEOUT"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.ClientTimeout = d
		}
	}
	if v, ok := env["REDIS_GC_THRESHOLD"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.GcThreshold = d
		}
	}
	if v, ok := env["REDIS_GC_DATABASES"]; ok {
		c.GcDatabases = v
	}
	if v, ok := env["REDIS_CONFIGURATION_MASTER_RETRIES"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.RedisMasterRetries = d
		}
	}
	if v, ok := env["REDIS_CONFIGURATION_MASTER_RETRY_INTERVAL"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.RedisMasterRetryInterval = d
		}
	}
	if v, ok := env["MAIL_TO"]; ok {
		c.MailTo = v
	}
	if v, ok := env["BEETLE_REDIS_SERVER"]; ok {
		c.RedisMasterFile = v
	}
	if v, ok := env["BEETLE_DIAL_TIMEOUT"]; ok {
		if d, err := strconv.Atoi(v); err == nil {
			c.DialTimeout = d
		}
	}
	if v, ok := env["REDIS_FAILOVER_CONFIDENCE_LEVEL"]; ok {
		c.ConfidenceLevel = v
	}
	c.Sanitize()
	return &c
}
