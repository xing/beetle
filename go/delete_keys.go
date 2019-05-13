package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gopkg.in/redis.v5"
)

// DeleteKeysOptions are provided by the caller of RunDeleteKeys.
type DeleteKeysOptions struct {
	RedisMasterFile string        // Path to the redis master file.
	Databases       string        // List of databases to scan.
	System          string        // Name of redis system for which to delete keys.
	Queue           string        // Name of the queue for which to delete all keys
	DeleteBefore    time.Duration // Delete keys which expire before the given time.
}

// DeleterState holds options and collector state, most importantly the current redis
// connection and database.
type DeleterState struct {
	opts          DeleteKeysOptions
	currentMaster string
	currentDB     int
	redis         *redis.Client // current connection
	keySuffixes   []string
}

func (s *DeleterState) key(msgId, suffix string) string {
	return fmt.Sprintf("%s:%s", msgId, suffix)
}

func (s *DeleterState) keys(msgId string) []string {
	res := make([]string, 0)
	for _, suffix := range s.keySuffixes {
		res = append(res, s.key(msgId, suffix))
	}
	return res
}

func (s *DeleterState) msgId(key string) string {
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]+):.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("msgid could not be extracted from key '%s'", key)
		return ""
	}
	return matches[1]
}

func (s *DeleterState) deleteMessageKeys(key string, threshold uint64) (bool, error) {
	v, err := s.redis.Get(key).Result()
	if err != nil {
		if err == redis.Nil {
			logDebug("key not found: %s", key)
			return false, nil
		}
		return false, err
	}
	expires, err := strconv.ParseUint(v, 10, 64)
	if err != nil {
		return false, err
	}
	if expires >= threshold {
		t := time.Duration(expires-threshold) * time.Second
		logDebug("key %s expires in %s", key, t)
		return false, err
	}
	t := time.Duration(threshold-expires) * time.Second
	logDebug("key %s has expired %s ago", key, t)
	msgID := s.msgId(key)
	if msgID == "" {
		return false, nil
	}
	keys := s.keys(msgID)
	// logDebug("deleting keys: %s", strings.Join(keys, ", "))
	_, err = s.redis.Del(keys...).Result()
	return err == nil, err
}

func (s *DeleterState) deleteKeys(db int) {
	var deleted int
	var cursor uint64
	defer func() { logInfo("deleted %d keys in db %d", deleted, db) }()
	ticker := time.NewTicker(1 * time.Second)
	keyPattern := "msgid:" + s.opts.Queue + ":*:expires"
	expiry := time.Now().Add(s.opts.DeleteBefore)
	logInfo("deleting keys for queue %s expiring before %s", s.opts.Queue, expiry.Format(time.RFC3339))
	threshold := uint64(expiry.Unix())
deleting:
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
			keys, cursor, err = s.redis.Scan(cursor, keyPattern, 10000).Result()
			if err != nil {
				logError("starting over: %v", err)
				cursor = 0
				deleted = 0
				continue deleting
			}
			logDebug("retrieved %d keys from db %d", len(keys), db)
			for _, key := range keys {
				if interrupted {
					return
				}
				removed, err := s.deleteMessageKeys(key, threshold)
				if err != nil {
					logError("starting over: %v", err)
					cursor = 0
					deleted = 0
					goto deleting
				}
				if removed {
					deleted++
				}
			}
			if cursor == 0 {
				return
			}
		}
	}
}

func (s *DeleterState) getMaster(db int) bool {
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

// RunDeleteKeys deletes all keys for a given queue on the redis
// master using the redis SCAN operation. Restarts from the beginning,
// should the master change while running the scan. Terminates as soon
// as a full scan has been performed on all databases.
func RunDeleteKeys(opts DeleteKeysOptions) error {
	logDebug("deleting keys with options: %+v", opts)
	state := &DeleterState{opts: opts}
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
			state.deleteKeys(db)
		}
	}
	if state.redis != nil {
		return state.redis.Close()
	}
	return nil
}
