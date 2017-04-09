package daemonize

import (
	"os"
	"testing"
)

func TestDaemonize(t *testing.T) {
	p, err := Daemonize(false, true)
	if err != nil {
		t.Fatalf("Daemonize failed: %v", err)
	}

	if p != nil {
		p.Wait()
		return
	}

	if pwd, _ := os.Getwd(); pwd != "/" {
		t.Errorf("Chdir failed (%s)", pwd)
	}
}
