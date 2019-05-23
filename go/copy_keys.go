package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gopkg.in/redis.v5"
)

// CopyKeysOptions are provided by the caller of RunCopyKeys.
type CopyKeysOptions struct {
	RedisMasterFile string        // Path to the redis master file.
	Databases       string        // List of databases to scan.
	System          string        // Name of redis system from which to copy keys.
	TargetRedis     string        // Redis connection spec of the system to copy keys to.
	QueuePrefix     string        // Copy keys for queues starting with the given prefix.
	CopyAfter       time.Duration // Copy keys which expire after the given time.
}

// CopyerState holds options and copier state, most importantly the current redis
// connection and database.
type CopierState struct {
	opts          CopyKeysOptions
	currentMaster string
	currentDB     int
	redis         *redis.Client // current source connection
	targetRedis   *redis.Client // target connection
	keySuffixes   []string
}

func (s *CopierState) key(msgId, suffix string) string {
	return fmt.Sprintf("%s:%s", msgId, suffix)
}

func (s *CopierState) keys(msgId string) []string {
	res := make([]string, 0)
	for _, suffix := range s.keySuffixes {
		res = append(res, s.key(msgId, suffix))
	}
	return res
}

func (s *CopierState) msgId(key string) string {
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]+):.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("msgid could not be extracted from key '%s'", key)
		return ""
	}
	return matches[1]
}

func (s *CopierState) matches(key string) string {
	re := regexp.MustCompile("^msgid:(" + s.opts.QueuePrefix + ".*):[-0-9a-f]+:.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		return ""
	}
	return matches[1]
}

func (s *CopierState) copyMessageKeys(key string, threshold uint64) (bool, error) {
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
	if expires < threshold {
		t := time.Duration(threshold-expires) * time.Second
		logDebug("key %s expires in %s", key, t)
		return false, err
	}
	t := time.Duration(expires-threshold) * time.Second
	logDebug("key %s will expire in %s", key, t)
	msgID := s.msgId(key)
	if msgID == "" {
		return false, nil
	}
	keys := s.keys(msgID)
	values, err := s.redis.MGet(keys...).Result()
	if err != nil {
		return false, err
	}
	pairs := make([]interface{}, 0, 2*len(keys))
	for i := range keys {
		if values[i] != nil {
			pairs = append(pairs, keys[i], values[i])
		}
	}
	logDebug("copying keys: %v", pairs)
	result, err := s.targetRedis.MSet(pairs...).Result()
	logDebug("copying keys returned: %v", result)
	return err == nil, err
}

func (s *CopierState) copyKeys(db int) {
	var copied int
	var cursor uint64
	defer func() { logInfo("copied %d keys from db %d", copied, db) }()
	ticker := time.NewTicker(100 * time.Millisecond)
	s.targetRedis = redis.NewClient(&redis.Options{Addr: s.opts.TargetRedis, DB: db})
	keyPattern := "msgid:" + s.opts.QueuePrefix + "*:expires"
	expiry := time.Now().Add(s.opts.CopyAfter)
	logInfo("copying keys for queue prefix '%s' expiring after %s", s.opts.QueuePrefix, expiry.Format(time.RFC3339))
	threshold := uint64(expiry.Unix())
copying:
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
			keys, cursor, err = s.redis.Scan(cursor, keyPattern, 1000).Result()
			if err != nil {
				logError("starting over: %v", err)
				cursor = 0
				copied = 0
				continue copying
			}
			for _, key := range keys {
				if interrupted {
					return
				}
				if s.matches(key) == "" {
					continue
				}
				ok, err := s.copyMessageKeys(key, threshold)
				if err != nil {
					logError("starting over: %v", err)
					cursor = 0
					copied = 0
					goto copying
				}
				if ok {
					copied++
				}
			}
			if cursor == 0 {
				return
			}
		}
	}
}

func (s *CopierState) getMaster(db int) bool {
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

// RunCopyKeys deletes all keys for a given queue on the redis
// master using the redis SCAN operation. Restarts from the beginning,
// should the master change while running the scan. Terminates as soon
// as a full scan has been performed on all databases.
func RunCopyKeys(opts CopyKeysOptions) error {
	logDebug("deleting keys with options: %+v", opts)
	state := &CopierState{opts: opts}
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
			state.copyKeys(db)
		}
	}
	if state.redis != nil {
		return state.redis.Close()
	}
	return nil
}
