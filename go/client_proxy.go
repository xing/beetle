package main

import (
	"fmt"
	"time"

	zmq "github.com/pebbe/zmq4"
)

type ClientProxyOptions struct {
	RedisMasterFile       string
	ClientProxyPort       int
	ClientProxyIP         string
	ExitAfterFileReceived bool
	Verbose               bool
}

func RunClientProxy(options ClientProxyOptions) error {
	logInfo("configuration client proxy started")
	defer logInfo("configuration client proxy terminated")

	frontend, err := zmq.NewSocket(zmq.SUB)
	if err != nil {
		logError("could not create configuration client proxy SUB socket")
		return err
	}
	defer frontend.Close()
	frontend.SetLinger(0)
	spec := fmt.Sprintf("tcp://%s:%d", options.ClientProxyIP, options.ClientProxyPort)
	frontend.Connect(spec)
	frontend.SetSubscribe("redis-master-file-content")

	poller := zmq.NewPoller()
	poller.Add(frontend, zmq.POLLIN)

	content := ReadRedisMasterFile(options.RedisMasterFile)

	for !interrupted {
		polled, err := poller.Poll(1000 * time.Millisecond)
		if err != nil {
			continue
		}
		for range polled {
			msg, err := frontend.RecvMessage(0)
			if err != nil {
				return err
			}
			topic := msg[0]
			newContent := msg[1]
			if options.Verbose {
				fmt.Printf("%s:\n%s\n", topic, newContent)
			}
			if newContent != content {
				err := WriteRedisMasterFile(options.RedisMasterFile, newContent)
				if err != nil {
					logError("could not update redis master file: %v", err)
					continue
				}
				content = newContent
			}
			if options.ExitAfterFileReceived {
				return nil
			}
		}
	}
	return nil
}
