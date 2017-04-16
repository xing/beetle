package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"reflect"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/davecgh/go-spew/spew"
)

var serverTestOptions = ServerOptions{ClientTimeout: 1}

func init() {
	if os.Getenv("V") != "1" {
		log.SetOutput(ioutil.Discard)
	}
}

func TestServerManagingUnresponsiveClients(t *testing.T) {
	fmt.Println("=== ServerManagingUnresponsiveClients ============================")
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
	if len(u) != 1 || u[0] != "b:2" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[b:2]', but is: '%v'", u)
	}
	// add an older client
	s.clientsLastSeen["c"] = older
	u = s.UnresponsiveClients()
	if len(u) != 2 || u[0] != "c:3" || u[1] != "b:2" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[c:3 b:2]', but is: '%v'", u)
	}

}

func checkEqual(t *testing.T, actual, expected interface{}) {
	if !reflect.DeepEqual(expected, actual) {
		t.Errorf("expected %+v to be equal to %+v", actual, expected)
		spew.Dump(actual, expected)
	}
}

func TestSplitProperties(t *testing.T) {
	fmt.Println("=== SplitProperties ==============================================")
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
	fmt.Println("=== TestSavingAndLoadingState  ===================================")
	s := NewServerState(serverTestOptions)
	s.currentMaster = NewRedisShim("127.0.0.1:6379")
	s.AddUnknownClientId("xxx")
	s.AddUnknownClientId("yyy")
	s.SaveState()
	old := s.unknownClientIds
	s.unknownClientIds = make(StringList, 0)
	s.LoadState()
	checkEqual(t, s.unknownClientIds, old)
}
