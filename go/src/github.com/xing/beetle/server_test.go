package main

import (
	"testing"
	"time"
)

var serverTestOptions = ServerOptions{ClientTimeout: 50 * time.Millisecond}

func TestServerManagingUnresponsiveClients(t *testing.T) {
	s := NewServerState(serverTestOptions)
	u := s.UnresponsiveClients()
	if len(u) != 0 {
		t.Errorf("initially, UnresponsiveClients() should be empty, but is: '%v'", u)
	}
	now := time.Now()
	recent := now.Add(-1 * time.Millisecond)
	old := now.Add(-1 * time.Second)
	older := now.Add(-2 * time.Second)
	// add a fresh client
	s.clientsLastSeen["a"] = recent
	u = s.UnresponsiveClients()
	if len(u) != 0 {
		t.Errorf("after adding a fresh client, UnresponsiveClients() should be empty, but is: '%v'", u)
	}
	// add an old client
	s.clientsLastSeen["b"] = old
	u = s.UnresponsiveClients()
	if len(u) != 1 || u[0] != "b:1" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[b:1]', but is: '%v'", u)
	}
	// add an older client
	s.clientsLastSeen["c"] = older
	u = s.UnresponsiveClients()
	if len(u) != 2 || u[0] != "c:2" || u[1] != "b:1" {
		t.Errorf("after adding an old client, UnresponsiveClients() should be '[c:2 b:1]', but is: '%v'", u)
	}

}
