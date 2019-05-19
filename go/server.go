package main

import (
	"os"
	"sync"
	"time"

	// "github.com/davecgh/go-spew/spew"
	"github.com/gobuffalo/packr"
	"github.com/xing/beetle/consul"
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

var (
	htmlTemplate    string
	gcStatsTemplate string
)

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

	// load html templates
	box := packr.NewBox("./templates")
	html, err := box.FindString("index.html")
	if err != nil {
		logError("could not load index.html")
		os.Exit(1)
	}
	htmlTemplate = html
	html, err = box.FindString("gcstats.html")
	if err != nil {
		logError("could not load gcstats.html")
		os.Exit(1)
	}
	gcStatsTemplate = html

	state.clientHandler(state.GetConfig().Port)
	logInfo("shutting down")
	// wait for web socket readers and writers to finish
	if waitForWaitGroupWithTimeout(&state.waitGroup, 3*time.Second) {
		logInfo("websocket readers and writers shut down timed out")
	} else {
		logInfo("websocket readers and writers finished cleanly")
	}
	return nil
}
