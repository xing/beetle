package main

import (
	"fmt"
	"log"
	"os"
	"sync/atomic"
	"time"
)

func init() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
}

func logInfo(format string, args ...interface{}) {
	finalFormat := fmt.Sprintf("I[%d] %s\n", os.Getpid(), format)
	log.Printf(finalFormat, args...)
}

func logDebug(format string, args ...interface{}) {
	if !Verbose {
		return
	}
	finalFormat := fmt.Sprintf("I[%d] %s\n", os.Getpid(), format)
	log.Printf(finalFormat, args...)
}

func logError(format string, args ...interface{}) {
	finalFormat := fmt.Sprintf("E[%d] %s\n", os.Getpid(), format)
	log.Printf(finalFormat, args...)
}

func logWarn(format string, args ...interface{}) {
	finalFormat := fmt.Sprintf("W[%d] %s\n", os.Getpid(), format)
	log.Printf(finalFormat, args...)
}

func (s *ServerState) statsReporter() {
	for !interrupted {
		time.Sleep(1 * time.Second)
		msgCount := atomic.SwapInt64(&processed, 0)
		connCount := atomic.LoadInt64(&wsConnections)
		logInfo("processed: %d, ws connections: %d", msgCount, connCount)
	}
}
