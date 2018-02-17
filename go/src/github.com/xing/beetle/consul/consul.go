package consul

import (
	"encoding/base64"
	"encoding/json"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/pkg/errors"
)

// Verbose defines the verbosity level
var Verbose = false

// Env is a string map
type Env map[string]string

// Entry is akey value pair
type Entry struct {
	Key   string
	Value string
}

// Entries is a slice of Entry objects used for sorting
type Entries []Entry

func (es Entries) Len() int {
	return len(es)
}
func (es Entries) Less(i, j int) bool {
	return es[i].Key < es[i].Key
}
func (es Entries) Swap(i, j int) {
	es[i], es[j] = es[j], es[i]
}

// Space represents a space in consul
type Space struct {
	prefix      string
	modifyIndex int
	entries     Entries
}

// Client is used to access consul
type Client struct {
	consulUrl    string
	appName      string
	appConfig    Space
	sharedConfig Space
	dataCenter   string
	dataCenters  []string
}

// NewClient creates a new consul client
func NewClient(consulUrl string, appName string) *Client {
	client := Client{
		consulUrl:    consulUrl,
		appName:      appName,
		appConfig:    Space{prefix: "apps/" + appName + "/config/"},
		sharedConfig: Space{prefix: "shared/config/"},
	}
	n := len(client.consulUrl)
	if n > 0 && client.consulUrl[n-1] != '/' {
		client.consulUrl += "/"
	}
	return &client
}

// Initialize determines the list of known datacenters and the datacenter we run
// in.
func (c *Client) Initialize() error {
	if err := c.GetDataCenters(); err != nil {
		return err
	}
	c.GetDC()
	if Verbose {
		log.Printf("dc=%v, alldcs=%v\n", c.dataCenter, c.dataCenters)
	}
	return nil
}

// GetDC retrieves the datacenter we run in
func (c *Client) GetDC() {
	fqdn := getFQDN()
	for _, dc := range c.dataCenters {
		if strings.Contains(fqdn, "."+dc+".") {
			c.dataCenter = dc
		}
	}
}

func (c *Client) kvUrl(key string) string {
	return c.consulUrl + "v1/kv/" + key
}

// GetDataCenters retrieves the list of known datacenters from consul
func (c *Client) GetDataCenters() error {
	fullUrl := c.kvUrl("datacenters") + "?raw"
	if Verbose {
		log.Printf("Fetching datacenters %s\n", fullUrl)
	}
	response, err := http.Get(fullUrl)
	if err != nil {
		return errors.Wrapf(err, "GET %q failed", fullUrl)
	}
	defer response.Body.Close()
	if Verbose {
		log.Printf("response: %d, OK: %d\n", response.StatusCode, http.StatusOK)
	}
	if response.StatusCode != http.StatusOK {
		return errors.New(response.Status)
	}
	body, err := ioutil.ReadAll(response.Body)
	if err != nil {
		return errors.Wrap(err, "read failed")
	}
	dcs := strings.Replace(string(body), " ", "", -1)
	c.dataCenters = strings.Split(dcs, ",")
	return nil
}

// GetData loads a key/value space from consul
func (c *Client) GetData(space *Space, useIndex bool) error {
	fullUrl := c.kvUrl(space.prefix) + "?recurse"
	if useIndex {
		fullUrl += "&index=" + strconv.Itoa(space.modifyIndex)
	}
	if Verbose {
		log.Printf("GET %s\n", fullUrl)
	}
	response, err := http.Get(fullUrl)
	if err != nil {
		return errors.Wrapf(err, "GET %q failed", fullUrl)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return errors.New(response.Status)
	}
	var body []byte
	if body, err = ioutil.ReadAll(response.Body); err != nil {
		return errors.Wrap(err, "read failed")
	}
	if index := response.Header.Get("X-Consul-Index"); index != "" {
		if Verbose {
			log.Printf("GET response: X-Consul-Index: %s", index)
		}
		var n int
		n, err = strconv.Atoi(index)
		if err != nil {
			return errors.Wrap(err, "conversion failed")
		}
		space.modifyIndex = n
	}
	if Verbose {
		log.Printf("GET response: %s", string(body))
	}
	if err = json.Unmarshal(body, &space.entries); err != nil {
		return errors.Wrap(err, "json unmarshal failed")
	}

	return nil
}

// GetEnv loads shared and app specific config from consul and returns it as a
// string map
func (c *Client) GetEnv() (env Env, err error) {
	if Verbose {
		log.Printf("Retrieving config hierarchies for %s from consul %s\n", c.appName, c.consulUrl)
	}
	if err = c.GetData(&c.sharedConfig, false); err != nil {
		return
	}
	if err = c.GetData(&c.appConfig, false); err != nil {
		return
	}
	env = c.CombineConfigs()
	return
}

// WatchConfig watches for consul changes in the background. Returns a channel
// on which to listen for new environments.
func (c *Client) WatchConfig() (chan Env, error) {
	changes := make(chan Env, 10)
	// Ensure we retrieve configs and keys at least once before launching go
	// routines, so that CombineConfigs() returns a full environment.
	if c.appConfig.entries == nil || c.sharedConfig.entries == nil {
		_, err := c.GetEnv()
		if err != nil {
			return nil, err
		}
	}
	go c.watchSpace(&c.appConfig, changes)
	go c.watchSpace(&c.sharedConfig, changes)
	return changes, nil
}

// Watches run forever. We rely on sockets being closed automatically when the
// program terminates.
func (c *Client) watchSpace(space *Space, channel chan Env) {
	for {
		oldIndex := space.modifyIndex
		err := c.GetData(space, true)
		if err != nil {
			log.Println(err)
			continue
		}
		if oldIndex != space.modifyIndex {
			channel <- c.CombineConfigs()
		}
	}
}

// Check whether we have a dc specific key, if so, remove the DC part of the key
func (c *Client) transformKeyAccordingToDC(key string) string {
	key = strings.ToLower(key)
	for _, dc := range c.dataCenters {
		dcPrefix := dc + "/"
		if strings.HasPrefix(key, dcPrefix) {
			if dc == c.dataCenter {
				return strings.Replace(key, dcPrefix, "", 1)
			}
			return ""
		}
	}
	return key
}

func (c *Client) addEntriesToEnv(space *Space, env Env) (err error) {
	// Sort the entries lexicographically. This way ensure data center specific keys overrride non specific keys.
	sort.Sort(space.entries)
	for _, x := range space.entries {
		if x.Value, err = decodeBase64(x.Value); err != nil {
			return
		}
		if space.prefix != "" {
			x.Key = strings.Replace(x.Key, space.prefix, "", 1)
		}
		x.Key = c.transformKeyAccordingToDC(x.Key)
		x.Key = strings.Replace(x.Key, "/", "_", -1)
		x.Key = strings.ToUpper(x.Key)
		if x.Key != "" && x.Key != "RESTART" && !strings.HasSuffix(x.Key, "_") {
			if Verbose {
				log.Printf("adding %s=%v\n", x.Key, x.Value)
			}
			env[x.Key] = x.Value
		}
	}
	return
}

// CombineConfigs combines shared config with app specific config
func (c *Client) CombineConfigs() (env Env) {
	env = make(Env)
	c.addEntriesToEnv(&c.sharedConfig, env)
	c.addEntriesToEnv(&c.appConfig, env)
	return
}

func decodeBase64(str string) (decoded string, err error) {
	var b []byte
	if b, err = base64.StdEncoding.DecodeString(str); err != nil {
		err = errors.Wrap(err, "base64 decode failed")
		return
	}
	decoded = string(b)
	return
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
