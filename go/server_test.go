package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/davecgh/go-spew/spew"
)

var serverTestOptions = ServerOptions{Config: &Config{ClientTimeout: 1, RedisServers: "beetle/127.0.0.1:7001,127.0.0.1:7002"}}
var testVerbosity int

func startAndWaitForText(cmd *exec.Cmd, text []string) {
	pipe, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Printf("could not obtain stdout of redis-server: %v", err)
		cmd.Process.Kill()
		os.Exit(1)
	}
	if testVerbosity > 1 {
		log.Println("starting redis server")
	}
	scanner := bufio.NewScanner(pipe)
	cmd.Start()
	for scanner.Scan() {
		line := scanner.Text()
		if testVerbosity > 1 {
			log.Println(line)
		}
		for _, marker := range text {
			if strings.Contains(line, marker) {
				if testVerbosity > 1 {
					log.Printf("redis server started: %s", marker)
				}
				return
			}
		}
	}
}

func TestMain(m *testing.M) {

	if v, err := strconv.Atoi(os.Getenv("V")); err == nil {
		testVerbosity = v
	}
	if testVerbosity == 0 {
		log.SetOutput(ioutil.Discard)
	}
	cmd, err := exec.LookPath("redis-server")
	if err != nil {
		fmt.Printf("could not find redis server. you need one to run the tests!")
		os.Exit(1)
	}
	redis1 := exec.Command(cmd, "--port", "7001")
	startAndWaitForText(redis1, []string{"server is now ready to accept connections", "Ready to accept connections"})
	redis2 := exec.Command(cmd, "--port", "7002", "--slaveof", "127.0.0.1", "7001")
	startAndWaitForText(redis2, []string{"MASTER <-> SLAVE sync: Finished with success", "MASTER <-> REPLICA sync: Finished with success"})
	result := m.Run()
	redis1.Process.Kill()
	redis2.Process.Kill()
	redis1.Wait()
	redis2.Wait()
	os.Exit(result)
}

func TestServerManagingUnresponsiveClients(t *testing.T) {
	s := NewServerState(serverTestOptions)
	u := s.UnresponsiveClients()
	if len(u) != 0 {
		t.Errorf("initially, UnresponsiveClients() should be empty, but is: '%v'", u)
	}
	now := time.Now()
	recent := now.Add(-1 * time.Millisecond)
	old := now.Add(-2 * time.Second)
	older := now.Add(-3 * time.Second)
	// add a fresh client
	s.clientsLastSeen["a"] = recent
	u = s.UnresponsiveClients()
	if len(u) != 0 {
		t.Errorf("after adding a fresh client, UnresponsiveClients() should be empty, but is: '%v'", u)
	}
	// add an old client
	s.clientsLastSeen["b"] = old
	u = s.UnresponsiveClients()
	if len(u) != 1 || u[0] != "b: last seen 2s ago" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[b: last seen 2s ago]', but is: '%v'", u)
	}
	// add an older client
	s.clientsLastSeen["c"] = older
	u = s.UnresponsiveClients()
	if len(u) != 2 || u[0] != "c: last seen 3s ago" || u[1] != "b: last seen 2s ago" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[c:last seen 3s ago 3 b: last seen 2s ago]', but is: '%v'", u)
	}

}

func checkEqual(t *testing.T, actual, expected interface{}) {
	if !reflect.DeepEqual(expected, actual) {
		t.Errorf("expected %+v to be equal to %+v", actual, expected)
		spew.Dump(actual, expected)
	}
}

func TestSplitProperties(t *testing.T) {
	s, expected := "", []string{""}
	actual := strings.Split(s, ",")
	checkEqual(t, actual, expected)

	s, expected = ",", []string{"", ""}
	actual = strings.Split(s, ",")
	checkEqual(t, actual, expected)

	s, expected = "a", []string{"a"}
	actual = strings.Split(s, ",")
	checkEqual(t, actual, expected)

	re := regexp.MustCompile(" *, *")
	s, expected = "", []string{""}
	actual = re.Split(s, -1)
	checkEqual(t, actual, expected)

	s, expected = "  ,,   ", []string{"", "", ""}
	actual = re.Split(s, -1)
	checkEqual(t, actual, expected)
}

func TestSavingAndLoadingState(t *testing.T) {
	s := NewServerState(serverTestOptions)
	s.failovers[s.systemNames[0]].currentMaster = NewRedisShim("127.0.0.1:7001", "", false)
	s.ClientSeen("xxx")
	s.ClientSeen("yyy")
	s.SaveState()
	oldLastSeen := s.clientsLastSeen
	s.clientsLastSeen = make(TimeSet)
	s.LoadState()
	if !s.clientsLastSeen.Equal(oldLastSeen) {
		t.Errorf("Could not load clients last seen state properly")
	}
}

func TestClientSeen(t *testing.T) {
	s := NewServerState(serverTestOptions)
	s.failovers[s.systemNames[0]].currentMaster = NewRedisShim("127.0.0.1:7001", "", false)
	if s.ClientSeen("xxx") {
		t.Errorf("server claims he's seen a client which it hasn't seen before. nuts?")
	}
	if !s.ClientSeen("xxx") {
		t.Errorf("server claims he's hasn't seen a client which it has seen before. nuts?")
	}
}

func TestUnknownClientIdsSorting(t *testing.T) {
	s := NewServerState(serverTestOptions)
	s.AddUnknownClientId("yyy")
	s.AddUnknownClientId("aaa")
	s.AddUnknownClientId("xxx")
	expected := []string{"aaa", "xxx", "yyy"}
	actual := s.UnknownClientIds()
	checkEqual(t, actual, expected)
}
