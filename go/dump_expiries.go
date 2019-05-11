package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gopkg.in/redis.v5"
)

// DumpExpiriesOptions are provided by the caller of RunDumpExpiries.
type DumpExpiriesOptions struct {
	RedisMasterFile string // Path to the redis master file.
	Databases       string // List of databases to scan.
	System          string // Name of redis system for which to delete keys.
}

// DumperState holds options and collector state, most importantly the current redis
// connection and database.
type DumperState struct {
	opts          DumpExpiriesOptions
	currentMaster string
	currentDB     int
	redis         *redis.Client // current connection
	keySuffixes   []string
}

func (s *DumperState) key(msgId, suffix string) string {
	return fmt.Sprintf("%s:%s", msgId, suffix)
}

func (s *DumperState) keys(msgId string) []string {
	res := make([]string, 0)
	for _, suffix := range s.keySuffixes {
		res = append(res, s.key(msgId, suffix))
	}
	return res
}

func (s *DumperState) msgId(key string) string {
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]+):.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("msgid could not be extracted from key '%s'", key)
		return ""
	}
	return matches[1]
}

func (s *DumperState) printExpiry(key string) (bool, error) {
	v, err := s.redis.Get(key).Result()
	if err != nil {
		if err == redis.Nil {
			logDebug("key not found: %s", key)
			return false, nil
		}
		return false, err
	}
	fmt.Printf("%s:%s\n", key, v)
	return true, nil
}

func (s *DumperState) dumpKeys(db int) {
	var dumped int
	var cursor uint64
	defer func() { logInfo("dumped %d keys in db %d", dumped, db) }()
	ticker := time.NewTicker(1 * time.Second)
dumping:
	for range ticker.C {
		if interrupted {
			return
		}
		if s.getMaster(db) {
			if cursor == 0 {
				logInfo("starting SCAN on db %d", db)
			}
			logDebug("cursor: %d", cursor)
			var err error
			var keys []string
			keys, cursor, err = s.redis.Scan(cursor, "msgid:*:expires", 10000).Result()
			if err != nil {
				logError("starting over: %v", err)
				cursor = 0
				dumped = 0
				continue dumping
			}
			logDebug("retrieved %d keys from db %d", len(keys), db)
			for _, key := range keys {
				if interrupted {
					return
				}
				printed, err := s.printExpiry(key)
				if err != nil {
					logError("starting over: %v", err)
					cursor = 0
					dumped = 0
					goto dumping
				}
				if printed {
					dumped++
				}
			}
			if cursor == 0 {
				return
			}
		}
	}
}

func (s *DumperState) getMaster(db int) bool {
	systems := RedisMastersFromMasterFile(s.opts.RedisMasterFile)
	server := systems[s.opts.System]
	if s.currentMaster != server || s.currentDB != db {
		s.currentMaster = server
		s.currentDB = db
		if server == "" {
			if s.redis != nil {
				s.redis.Close()
			}
			s.redis = nil
		} else {
			s.redis = redis.NewClient(&redis.Options{Addr: server, DB: db})
		}
	}
	if s.redis == nil {
		logError("could not determine redis master: %v, db: %d", s.currentMaster, db)
	}
	return s.redis != nil
}

// RunDumpExpiries deletes all keys for a given queue on the redis
// master using the redis SCAN operation. Restarts from the beginning,
// should the master change while running the scan. Terminates as soon
// as a full scan has been performed on all databases.
func RunDumpExpiries(opts DumpExpiriesOptions) error {
	logDebug("dumping keys with options: %+v", opts)
	state := &DumperState{opts: opts}
	state.keySuffixes = []string{"status", "ack_count", "timeout", "delay", "attempts", "exceptions", "mutex", "expires"}
	for _, s := range strings.Split(opts.Databases, ",") {
		if interrupted {
			break
		}
		if s != "" {
			db, err := strconv.Atoi(s)
			if err != nil {
				logError("%v", err)
				continue
			}
			state.dumpKeys(db)
		}
	}
	if state.redis != nil {
		return state.redis.Close()
	}
	return nil
}
