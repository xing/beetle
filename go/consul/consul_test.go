package consul

import (
	"fmt"
	"io/ioutil"
	"log"
	"math/rand"
	"os"
	"os/exec"
	"reflect"
	"strconv"
	"testing"
	"time"
)

var testUrl = ""
var testApp = "beetle"

func init() {
	log.SetFlags(0)
	Verbose = os.Getenv("V") == "1"
	if !Verbose {
		log.SetOutput(ioutil.Discard)
	}
	testUrl = "http://localhost:8500"
	cmd := exec.Command("curl", "-X", "PUT", testUrl+"/v1/kv/datacenters", "-d", "ams1,ams2")
	if err := cmd.Run(); err != nil {
		fmt.Errorf("could not set up datacenters")
	}
	cmd = exec.Command("curl", "-X", "PUT", testUrl+"/v1/kv/apps/beetle/config/")
	if err := cmd.Run(); err != nil {
		fmt.Errorf("could not set up beetle config")
	}
	cmd = exec.Command("curl", "-X", "PUT", testUrl+"/v1/kv/shared/config/")
	if err := cmd.Run(); err != nil {
		fmt.Errorf("could not set up shared config")
	}
}

func TestConnect(t *testing.T) {
	client := NewClient(testUrl, testApp)
	client.Initialize()
	if !reflect.DeepEqual(client.dataCenters, []string{"ams1", "ams2"}) {
		t.Errorf("could not retrieve datacenters: %v", client.dataCenters)
	}
	if _, err := client.GetEnv(); err != nil {
		t.Errorf("could not retrieve environment: %s", err)
	}
}
func TestState(t *testing.T) {
	client := NewClient(testUrl, testApp)
	client.Initialize()
	value := strconv.Itoa(rand.Int())
	if err := client.UpdateState("test", value); err != nil {
		t.Errorf("could not set test key: %s", err)
	}
	kv, err := client.GetState()
	if err != nil {
		t.Errorf("could not get state keys: %s", err)
	}
	if kv["test"] != value {
		t.Errorf("retrieved test keys have wrong value: %+v", kv)
	}
}

func TestWatching(t *testing.T) {
	client := NewClient(testUrl, testApp)
	client.Initialize()
	channel, err := client.WatchConfig()
	if err != nil {
		t.Errorf("could not start watching: %v", err)
	}
	select {
	case <-channel:
		t.Errorf("we should not have received a new env")
	case <-time.After(250 * time.Millisecond):
		// this is what we expect
	}
	if os.Getenv("EDITCONSUL") == "1" {
		fmt.Println("please change something in consul")
		select {
		case env := <-channel:
			// this is what we expect
			fmt.Printf("new env: %+v", env)
		case <-time.After(10 * time.Second):
			t.Errorf("we should have received a new env")
		}
	}
}
