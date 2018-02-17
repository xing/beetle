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
	"bitbucket.org/madmo/daemonize"
	"github.com/jessevdk/go-flags"
	"github.com/xing/beetle/consul"
	"gopkg.in/yaml.v2"
)

var opts struct {
	Verbose                  bool   `short:"v" long:"verbose" description:"Be verbose."`
	Daemonize                bool   `short:"d" long:"daemonize" description:"Run as a daemon. Use with --log-file."`
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
	ConsulUrl                string `long:"consul" optional:"t" optional-value:"http://127.0.0.1:8500" description:"Specifies consul server url to use for retrieving config values. If given without argument, tries to contact local consul agent."`
	GcThreshold              int    `long:"redis-gc-threshold" description:"Number of seconds to wait until considering an expired redis key eligible for garbage collection. Defaults to 3600 (1 hour)."`
	GcDatabases              string `long:"redis-gc-databases" description:"Database numbers to collect keys from (e.g. 0,4). Defaults to 4."`
	MailTo                   string `long:"mail-to" description:"Send notifcation mails to this address."`
	DialTimeout              int    `long:"dial-timeout" description:"Number of seconds to wait until a connection attempt to the master times out. Defaults to 5."`
}

// Verbose stores verbosity or logging purposoes.
var Verbose bool

var cmd flags.Commander
var cmdArgs []string

// CmdRunClient is used when the program arguments tell us run a client.
type CmdRunClient struct{}

var cmdRunClient CmdRunClient

// Execute runs a configuration client.
func (x *CmdRunClient) Execute(args []string) error {
	return RunConfigurationClient(ClientOptions{
		Id:           opts.Id,
		Config:       initialConfig,
		ConsulClient: getConsulClient(),
	})
}

// CmdRunServer is used when the program arguments tell us to run a server.
type CmdRunServer struct{}

var cmdRunServer CmdRunServer

// Execute runs a configuration server.
func (x *CmdRunServer) Execute(args []string) error {
	return RunConfigurationServer(ServerOptions{
		Config:       initialConfig,
		ConsulClient: getConsulClient(),
	})
}

// CmdRunMailer is used when the program arguments tell us to run a mailer.
type CmdRunMailer struct{}

var cmdRunMailer CmdRunMailer

// Execute runs a mailer.
func (x *CmdRunMailer) Execute(args []string) error {
	return RunNotificationMailer(MailerOptions{
		Server:      initialConfig.Server,
		Port:        initialConfig.Port,
		Recipient:   initialConfig.MailTo,
		DialTimeout: initialConfig.DialTimeout,
	})
}

// CmdPrintConfig is used when the program arguments tell us to print the configuration.
type CmdPrintConfig struct{}

var cmdPrintConfig CmdPrintConfig

// Execute prints the configuration.
func (x *CmdPrintConfig) Execute(args []string) error {
	fmt.Print(initialConfig.String())
	return nil
}

// CmdRunGCKeys is used when the program arguments tell us to garbage collect redis keys.
type CmdRunGCKeys struct{}

var cmdRunGCKeys CmdRunGCKeys

// Execute garbage collects redis keys.
func (x *CmdRunGCKeys) Execute(args []string) error {
	return RunGarbageCollectKeys(GCOptions{
		RedisMasterFile: initialConfig.RedisMasterFile,
		GcThreshold:     initialConfig.GcThreshold,
		GcDatabases:     initialConfig.GcDatabases,
	})
}

func init() {
	ReportVersionIfRequestedAndExit()
	opts.Id = getFQDN()
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
		logInfo("received TERM signal")
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

func getProgramParameters() *Config {
	return &Config{
		Server:                   opts.Server,
		Port:                     opts.Port,
		RedisServers:             opts.RedisServers,
		ClientIds:                opts.ClientIds,
		ClientHeartbeat:          opts.ClientHeartbeatInterval,
		ClientTimeout:            opts.ClientTimeout,
		RedisMasterRetries:       opts.RedisMasterRetries,
		RedisMasterRetryInterval: opts.RedisMasterRetryInterval,
		RedisMasterFile:          opts.RedisMasterFile,
		GcThreshold:              opts.GcThreshold,
		GcDatabases:              opts.GcDatabases,
		MailTo:                   opts.MailTo,
		DialTimeout:              opts.DialTimeout,
	}
}

func readConfigFile(configFile string) *Config {
	if configFile == "" {
		return nil
	}
	yamlFile, err := ioutil.ReadFile(configFile)
	if err != nil {
		logInfo("Could not read yaml file: %v", err)
		return nil
	}
	var c Config
	err = yaml.Unmarshal(yamlFile, &c)
	if err != nil {
		logError("Could not parse config file: %v", err)
		os.Exit(1)
	}
	return &c
}

func readConsulData(consulUrl string) (consul.Env, error) {
	if consulUrl == "" {
		return nil, nil
	}
	logInfo("retrieving config from consul: %s", consulUrl)
	client := getConsulClient()
	env, err := client.GetEnv()
	if err != nil {
		logInfo("could not retrieve config from consul: %v", err)
		return nil, err
	}
	return env, nil
}

var consulClient *consul.Client

func getConsulClient() *consul.Client {
	if opts.ConsulUrl != "" && consulClient == nil {
		consulClient = consul.NewClient(opts.ConsulUrl, "beetle")
	}
	return consulClient
}

var (
	configFromParams *Config
	configFromFile   *Config
	initialConfig    *Config
)

func setupConfig() error {
	configFromParams = getProgramParameters()
	configFromFile = readConfigFile(opts.ConfigFile)
	consulEnv, err := readConsulData(opts.ConsulUrl)
	if err != nil {
		return err
	}
	initialConfig = buildConfig(consulEnv)
	return nil
}

func buildConfig(env consul.Env) *Config {
	consulConfig := configFromConsulEnv(env)
	return configFromParams.Clone().Merge(configFromFile).Merge(consulConfig).SetDefaults()
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
	parser.AddCommand("dump", "dump configuration after merging all config sources and exit", "", &cmdPrintConfig)
	parser.AddCommand("garbage_collect_deduplication_store", "garbage collect keys on redis server", "", &cmdRunGCKeys)
	parser.AddCommand("notification_mailer", "listen to system notifications and send them via /usr/sbin/sendmail", "", &cmdRunMailer)
	parser.CommandHandler = cmdHandler

	_, err := parser.Parse()
	if err != nil {
		if err.(*flags.Error).Type == flags.ErrHelp {
			os.Exit(0)
		} else {
			os.Exit(1)
		}
	}
	if cmd != &cmdPrintConfig {
		redirectStdoutAndStderr(opts.LogFile)
		if opts.Daemonize {
			nochdir, noclose := true, false
			child, err := daemonize.Daemonize(nochdir, noclose)
			if err != nil {
				fmt.Println(err)
				os.Exit(1)
			}
			if child != nil {
				os.Exit(0)
			}
			logInfo("daemon started")
		}
	}
	Verbose = opts.Verbose
	consul.Verbose = Verbose
	err = setupConfig()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	logDebug("config has been set up")
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
