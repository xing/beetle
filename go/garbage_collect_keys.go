package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"gopkg.in/redis.v5"
)

// GCOptions are provided by the caller of RunGarbageCollectKeys.
type GCOptions struct {
	RedisMasterFile string // Path to the redis master file.
	GcThreshold     int    // Number of seconds after which a key should be considered collectible.
	GcDatabases     string // List of databases to scan.
	GcKeyFile       string // Name of file containing keys to collect.
	GcSystem        string // Name of redis system for which to collect keys.
}

// GCState holds options and collector state, most importantly the current redis
// connection and database.
type GCState struct {
	opts          GCOptions
	currentMaster string
	currentDB     int
	redis         *redis.Client // current connection
	keySuffixes   []string
	expiries      map[string]map[int]int
}

func (s *GCState) key(msgId, suffix string) string {
	return fmt.Sprintf("%s:%s", msgId, suffix)
}

func (s *GCState) keys(msgId string) []string {
	res := make([]string, 0)
	for _, suffix := range s.keySuffixes {
		res = append(res, s.key(msgId, suffix))
	}
	return res
}

func (s *GCState) msgId(key string) string {
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]+):.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("msgid could not be extracted from key '%s'", key)
		return ""
	}
	return matches[1]
}

func (s *GCState) msgQueueName(key string) string {
	re := regexp.MustCompile("^msgid:([^:]+):[-0-9a-f]+:.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("queue name could not be extracted from key '%s'", key)
		return ""
	}
	logDebug("queue name: %s", matches[1])
	return matches[1]
}

func (s *GCState) recordExpiryHour(key string, t time.Duration) {
	queue := s.msgQueueName(key)
	if queue == "" {
		return
	}
	expiriesForQueue, ok := s.expiries[queue]
	if !ok {
		expiriesForQueue = make(map[int]int)
		s.expiries[queue] = expiriesForQueue
	}
	hour := int(math.Ceil(t.Hours()))
	expiriesForQueue[hour]++
}

func (s *GCState) resetExpiries() {
	s.expiries = make(map[string]map[int]int)
}

type queueInfo struct {
	queue         string
	totalExpiries int
}
type queueInfos []queueInfo

func (s queueInfos) Len() int {
	return len(s)
}

func (s queueInfos) Less(i, j int) bool {
	return s[i].totalExpiries > s[j].totalExpiries
}

func (s queueInfos) Swap(i, j int) {
	s[i], s[j] = s[j], s[i]
}

type hourInfo struct {
	hour  int
	count int
}
type hourInfos []hourInfo

func (s hourInfos) Len() int {
	return len(s)
}

func (s hourInfos) Less(i, j int) bool {
	return s[i].hour > s[j].hour
}

func (s hourInfos) Swap(i, j int) {
	s[i], s[j] = s[j], s[i]
}

func (s *GCState) dumpExpiries() {
	l := make(queueInfos, 0, len(s.expiries))
	for q, m := range s.expiries {
		i := queueInfo{queue: q}
		for _, v := range m {
			i.totalExpiries += v
		}
		l = append(l, i)
	}
	sort.Sort(l)
	for _, i := range l {
		fmt.Println("--------------------------------------------------------------")
		fmt.Printf("%s: %d\n", i.queue, i.totalExpiries)
		fmt.Println("--------------------------------------------------------------")
		h := make(hourInfos, 0, len(s.expiries[i.queue]))
		for k, v := range s.expiries[i.queue] {
			h = append(h, hourInfo{hour: k, count: v})
		}
		sort.Sort(h)
		for _, hi := range h {
			fmt.Printf("%3dh: %5d\n", hi.hour, hi.count)
		}
	}
}

func (s *GCState) gcKey(key string, threshold uint64) (bool, error) {
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
		s.recordExpiryHour(key, t)
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

func (s *GCState) garbageCollectKeys(db int) {
	var total, expired int
	var cursor uint64
	defer func() { s.dumpExpiries() }()
	defer func() { logInfo("expired %d keys out of %d in db %d", expired, total, db) }()
	ticker := time.NewTicker(1 * time.Second)
collecting:
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
				total = 0
				expired = 0
				continue collecting
			}
			logDebug("retrieved %d keys from db %d", len(keys), db)
			total += len(keys)
			threshold := time.Now().Unix() + int64(s.opts.GcThreshold)
			for _, key := range keys {
				if interrupted {
					return
				}
				collected, err := s.gcKey(key, uint64(threshold))
				if err != nil {
					logError("starting over: %v", err)
					cursor = 0
					total = 0
					expired = 0
					goto collecting
				}
				if collected {
					expired++
				}
			}
			if cursor == 0 {
				return
			}
		}
	}
}

func (s *GCState) garbageCollectKeysFromFile(db int, filePath string) {
	var total, expired int
	defer func() { logInfo("expired %d keys out of %d in db %d", expired, total, db) }()

	file, err := os.Open(filePath)
	if err != nil {
		logError("%v", err)
		return
	}
	defer file.Close()

	s.getMaster(db)

	threshold := time.Now().Unix() + int64(s.opts.GcThreshold)
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]+):expires$")
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		if interrupted {
			break
		}
		line := scanner.Text()
		if !re.MatchString(line) {
			continue
		}
		total++
		collected, err := s.gcKey(line, uint64(threshold))
		if err != nil {
			logError("could not collect %s: %v", line, err)
			continue
		}
		if collected {
			expired++
		}
	}
	if err := scanner.Err(); err != nil {
		logError("%v", err)
	}
}

func (s *GCState) getMaster(db int) bool {
	systems := RedisMastersFromMasterFile(s.opts.RedisMasterFile)
	server := systems[s.opts.GcSystem]
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

// RunGarbageCollectKeys runs a garbage collection on the redis master using the
// redis SCAN operation. Restarts from the beginning, should the master change
// while running the scan. Terminates as soon as a full scan has been performed
// on all databases which need GC.
func RunGarbageCollectKeys(opts GCOptions) error {
	logDebug("garbage collecting keys with options: %+v", opts)
	state := &GCState{opts: opts}
	state.keySuffixes = []string{"status", "ack_count", "timeout", "delay", "attempts", "exceptions", "mutex", "expires"}
	for _, s := range strings.Split(opts.GcDatabases, ",") {
		if interrupted {
			break
		}
		if s != "" {
			db, err := strconv.Atoi(s)
			if err != nil {
				logError("%v", err)
				continue
			}
			state.resetExpiries()
			if opts.GcKeyFile == "" {
				state.garbageCollectKeys(db)
			} else {
				state.garbageCollectKeysFromFile(db, opts.GcKeyFile)
			}
		}
	}
	if state.redis != nil {
		return state.redis.Close()
	}
	return nil
}
