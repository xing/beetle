package main

import (
	"fmt"
	"os"
	"sync/atomic"
	"time"
)

func logInfo(format string, args ...interface{}) {
	final_format := fmt.Sprintf("I[%d] %s\n", os.Getpid(), format)
	fmt.Printf(final_format, args...)
}

func logDebug(format string, args ...interface{}) {
	if !Verbose {
		return
	}
	final_format := fmt.Sprintf("I[%d] %s\n", os.Getpid(), format)
	fmt.Printf(final_format, args...)
}

func logError(format string, args ...interface{}) {
	final_format := fmt.Sprintf("E[%d] %s\n", os.Getpid(), format)
	fmt.Fprintf(os.Stderr, final_format, args...)
}

func logWarn(format string, args ...interface{}) {
	final_format := fmt.Sprintf("W[%d] %s\n", os.Getpid(), format)
	fmt.Fprintf(os.Stderr, final_format, args...)
}

func (s *ServerState) statsReporter() {
	for !interrupted {
		time.Sleep(1 * time.Second)
		msg_count := atomic.SwapInt64(&processed, 0)
		conn_count := atomic.LoadInt64(&ws_connections)
		logInfo("processed: %d, ws connections: %d", msg_count, conn_count)
	}
}
