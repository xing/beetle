package main

import (
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	_ "embed"

	// "github.com/davecgh/go-spew/spew"
	"github.com/xing/beetle/consul"
)

var (
	//go:embed templates/index.html
	htmlTemplate string
	//go:embed templates/gcstats.html
	gcStatsTemplate string
	//go:embed templates/message.html
	messageTemplate string
)

// waits on a sync.WaitGroup, but times out after given duration.
func waitForWaitGroupWithTimeout(wg *sync.WaitGroup, timeout time.Duration) bool {
	c := make(chan struct{})
	go func() {
		defer close(c)
		wg.Wait()
	}()
	select {
	case <-c:
		return false
	case <-time.After(timeout):
		return true
	}
}

func waitForInterrupt() {
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGINT, syscall.SIGTERM)
	<-done
	logInfo("received interrupt")
}

// RunConfigurationServer implements the main server loop.
func RunConfigurationServer(o ServerOptions) error {
	logInfo("server started with options: %+v\n", o)
	state := NewServerState(o)
	state.Initialize()
	// start threads
	go state.dispatcher()
	if Verbose {
		go state.statsReporter()
	}
	if state.opts.ConsulClient != nil {
		var err error
		state.configChanges, err = state.opts.ConsulClient.WatchConfig()
		if err != nil {
			return err
		}
	} else {
		state.configChanges = make(chan consul.Env)
	}

	srv := state.setupClientHandler(state.GetConfig().Port)
	go state.runClientHandler(srv)
	waitForInterrupt()
	state.shutdownClientHandler(srv, 3*time.Second)

	logInfo("shutting down")
	// wait for web socket readers and writers to finish
	if waitForWaitGroupWithTimeout(&state.waitGroup, 3*time.Second) {
		logInfo("websocket readers and writers shut down timed out")
	} else {
		logInfo("websocket readers and writers finished cleanly")
	}
	return nil
}
