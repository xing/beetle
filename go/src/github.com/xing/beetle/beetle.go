package main

import (
	"fmt"
	"io/ioutil"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"

	// "github.com/davecgh/go-spew/spew"
	"github.com/jessevdk/go-flags"
	"gopkg.in/yaml.v2"
)

var opts struct {
	Verbose                  bool   `short:"v" long:"verbose" description:"Be verbose."`
	Id                       string `long:"id" env:"HOST" description:"Set unique client id."`
	ClientIds                string `long:"client-ids" description:"Clients that have to acknowledge on master switch (e.g. client-id1,client-id2)."`
	ClientTimeout            int    `long:"client-timeout" description:"Number of seconds to wait until considering a client dead (or unreachable). Defaults to 10."`
	ClientHeartbeatInterval  int    `long:"client-heartbeat-interval" description:"Number of seconds between client heartbeats. Defaults to 5."`
	ConfigFile               string `long:"config-file" description:"Config file path."`
	RedisServers             string `long:"redis-servers" description:"List of redis servers (comma separated, host:port pairs)."`
	RedisMasterFile          string `long:"redis-master-file" description:"Path of redis master file."`
	RedisMasterRetries       int    `long:"redis-master-retries" description:"How often to retry checking the availability of the current master before initiating a switch. Defaults to 3."`
	RedisMasterRetryInterval int    `long:"redis-master-retry-interval" description:"Number of seconds to wait between master checks. Defaults to 10."`
	PidFile                  string `long:"pid-file" description:"Write process id into given path."`
	LogFile                  string `long:"log-file" description:"Redirect stdout and stderr to the given path."`
	Server                   string `long:"server" description:"Specifies config server address."`
	Port                     int    `long:"port" description:"Port to use for web socket connections. Defaults to 9650."`
}

func setDefaults() {
	// If you change any of these values, don't forget to change the description above.
	if opts.ClientTimeout == 0 {
		opts.ClientTimeout = 10
	}
	if opts.ClientHeartbeatInterval == 0 {
		opts.ClientHeartbeatInterval = 5
	}
	if opts.RedisMasterRetries == 0 {
		opts.RedisMasterRetries = 3
	}
	if opts.RedisMasterRetryInterval == 0 {
		opts.RedisMasterRetryInterval = 10
	}
	if opts.Server == "" {
		opts.Server = "127.0.0.1"
	}
	if opts.Port == 0 {
		opts.Port = 9650
	}
}

var Verbose bool

var cmd flags.Commander
var cmdArgs []string

// run client
type CmdRunClient struct{}

var cmdRunClient CmdRunClient

func (x *CmdRunClient) Execute(args []string) error {
	return RunConfigurationClient(ClientOptions{
		Server:            opts.Server,
		Port:              opts.Port,
		Id:                opts.Id,
		RedisMasterFile:   opts.RedisMasterFile,
		HeartbeatInterval: opts.ClientHeartbeatInterval,
	})
}

// run server
type CmdRunServer struct{}

var cmdRunServer CmdRunServer

func (x *CmdRunServer) Execute(args []string) error {
	return RunConfigurationServer(ServerOptions{
		Port:                     opts.Port,
		ClientIds:                opts.ClientIds,
		ClientTimeout:            opts.ClientTimeout,
		ClientHeartbeat:          opts.ClientHeartbeatInterval,
		RedisServers:             opts.RedisServers,
		RedisMasterFile:          opts.RedisMasterFile,
		RedisMasterRetries:       opts.RedisMasterRetries,
		RedisMasterRetryInterval: opts.RedisMasterRetryInterval,
	})
}

func init() {
	ReportVersionIfRequestedAndExit()
	opts.Id = getFQDN()
	opts.RedisMasterFile = "/etc/beetle/redis-master"
	opts.ConfigFile = "/etc/beetle/beetle.yml"
}

func getFQDN() string {
	if host := os.Getenv("HOST"); host != "" {
		return host
	}
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	addrs, err := net.LookupIP(hostname)
	if err != nil {
		return hostname
	}
	for _, addr := range addrs {
		if ipv4 := addr.To4(); ipv4 != nil {
			ip, err := ipv4.MarshalText()
			if err != nil {
				return hostname
			}
			hosts, err := net.LookupAddr(string(ip))
			if err != nil || len(hosts) == 0 {
				return hostname
			}
			fqdn := hosts[0]
			return strings.TrimSuffix(fqdn, ".")
		}
	}
	return hostname
}

var interrupted bool

func installSignalHandler() {
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		interrupted = true
		signal.Stop(c)
	}()
}

func writePidFile(path string) {
	if path == "" {
		return
	}
	pid := strconv.Itoa(os.Getpid())
	err := ioutil.WriteFile(opts.PidFile, []byte(pid), 0644)
	if err != nil {
		fmt.Printf("could not write pid file %s: %s", path, err)
		os.Exit(1)
	}
}

func removePidFile(path string) {
	if path == "" {
		return
	}
	err := os.Remove(path)
	if err != nil {
		fmt.Printf("could not remove pid file %s: %s", path, err)
	}
}

func redirectStdoutAndStderr(path string) {
	if path == "" {
		return
	}
	// see https://github.com/golang/go/issues/325
	logFile, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_SYNC|os.O_APPEND, 0644)
	if err != nil {
		fmt.Printf("could not open log file: %s\n", err)
		return
	}
	syscall.Dup2(int(logFile.Fd()), 1)
	syscall.Dup2(int(logFile.Fd()), 2)
}

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
	LogFile                  string `yaml:"log_file"`
}

func readConfigFile() {
	if opts.ConfigFile == "" {
		return
	}
	var c Config
	yamlFile, err := ioutil.ReadFile(opts.ConfigFile)
	if err != nil {
		logInfo("Could not read yaml file: %v", err)
		return
	}
	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		logError("Could not parse config file: %v", err)
		os.Exit(1)
	}
	if opts.Server == "" {
		opts.Server = c.Server
	}
	if opts.Port == 0 {
		opts.Port = c.Port
	}
	if opts.RedisServers == "" {
		opts.RedisServers = c.RedisServers
	}
	if opts.ClientIds == "" {
		opts.ClientIds = c.ClientIds
	}
	if opts.ClientTimeout == 0 {
		opts.ClientTimeout = c.ClientTimeout
	}
	if opts.ClientHeartbeatInterval == 0 {
		opts.ClientHeartbeatInterval = c.ClientHeartbeat
	}
	if opts.RedisMasterRetries == 0 {
		opts.RedisMasterRetries = c.RedisMasterRetries
	}
	if opts.RedisMasterRetryInterval == 0 {
		opts.RedisMasterRetryInterval = c.RedisMasterRetryInterval
	}
	if opts.RedisMasterFile == "" {
		opts.RedisMasterFile = c.RedisMasterFile
	}
	if opts.LogFile == "" {
		opts.LogFile = c.LogFile
	}
}

func main() {
	cmdHandler := func(command flags.Commander, args []string) error {
		cmd = command
		cmdArgs = args
		return nil
	}
	parser := flags.NewParser(&opts, flags.Default)
	parser.AddCommand("configuration_client", "run redis configuration client", "", &cmdRunClient)
	parser.AddCommand("configuration_server", "run redis configuration server", "", &cmdRunServer)
	parser.CommandHandler = cmdHandler

	_, err := parser.Parse()
	if err != nil {
		if err.(*flags.Error).Type == flags.ErrHelp {
			os.Exit(0)
		} else {
			os.Exit(1)
		}
	}
	Verbose = opts.Verbose
	readConfigFile()
	setDefaults()
	redirectStdoutAndStderr(opts.LogFile)
	installSignalHandler()
	writePidFile(opts.PidFile)
	err = cmd.Execute(cmdArgs)
	removePidFile(opts.PidFile)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	os.Exit(0)
}
