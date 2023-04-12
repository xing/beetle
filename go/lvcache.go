//
//  Last value cache
//  Uses XPUB subscription messages to re-send data
//

package main

import (
	"fmt"
	"time"

	zmq "github.com/pebbe/zmq4"
)

func RunLVCache(initialValues map[string]string, client_proxy_port int) {
	frontend, err := zmq.NewSocket(zmq.SUB)
	if err != nil {
		logError("could not create internal value cache SUB socket")
		return
	}
	frontend.SetLinger(0)
	err = frontend.Bind("inproc://lv-cache")
	if err != nil {
		logError("could not bind internal value cache XPUB socket")
		return
	}
	backend, err := zmq.NewSocket(zmq.XPUB)
	if err != nil {
		logError("could not create internal value cache XPUB socket")
		return
	}
	backend.SetXpubVerbose(1)
	spec := fmt.Sprintf("tcp://*:%d", client_proxy_port)
	err = backend.Bind(spec)
	if err != nil {
		logError("could not bind internal value cache XPUB socket")
		return
	}

	//  Subscribe to every single topic from publisher
	frontend.SetSubscribe("")

	//  Store last instance of each topic in a cache
	cache := make(map[string]string)
	for k, v := range initialValues {
		cache[k] = v
	}

	//  We route topic updates from frontend to backend, and
	//  we handle subscriptions by sending whatever we cached,
	//  if anything:
	poller := zmq.NewPoller()
	poller.Add(frontend, zmq.POLLIN)
	poller.Add(backend, zmq.POLLIN)
LOOP:
	for !interrupted {
		polled, err := poller.Poll(1000 * time.Millisecond)
		if err != nil {
			break //  Interrupted
		}

		for _, item := range polled {
			switch socket := item.Socket; socket {
			case frontend:
				//  Any new topic data we cache and then forward
				msg, err := frontend.RecvMessage(0)
				if err != nil {
					break LOOP
				}
				cache[msg[0]] = msg[1]
				backend.SendMessage(msg)
			case backend:
				//  When we get a new subscription we pull data from the cache:
				msg, err := backend.RecvMessage(0)
				if err != nil {
					break LOOP
				}
				frame := msg[0]
				//  Event is one byte 0=unsub or 1=sub, followed by topic
				if frame[0] == 1 {
					topic := frame[1:]
					previous, ok := cache[topic]
					if ok {
						logInfo("sending cached topic: %s: %s", topic, previous)
						backend.SendMessage(topic, previous)
					}
				}
			}
		}
	}
}
