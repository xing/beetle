package consul

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"reflect"
	"testing"
	"time"
)

var testUrl = ""
var testApp = "activities"

func init() {
	log.SetFlags(0)
	Verbose = os.Getenv("V") == "1"
	if !Verbose {
		log.SetOutput(ioutil.Discard)
	}
	testUrl = os.Getenv("BEETLE_CONSUL_TEST_URL")
	if testUrl == "" {
		fmt.Println("BEETLE_CONSUL_TEST_URL needs to be set to the consul url used for testing (e.g. your preview server)")
		os.Exit(1)
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
