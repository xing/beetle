package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"golang.org/x/text/language"
	"golang.org/x/text/message"
	"gopkg.in/redis.v5"
)

var printer *message.Printer

func init() {
	printer = message.NewPrinter(language.English)
}

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
	orphans       map[string]int
	cursor        uint64
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
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]*):.*$")
	matches := re.FindStringSubmatch(key)
	if len(matches) == 0 {
		logError("msgid could not be extracted from key '%s'", key)
		return ""
	}
	return matches[1]
}

func (s *GCState) msgQueueName(key string) string {
	re := regexp.MustCompile("^msgid:([^:]+):[-0-9a-f]*:.*$")
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
	s.orphans = make(map[string]int)
}

type QueueInfo struct {
	Queue         string    `json:"queue"`
	TotalExpiries int       `json:"total_expiries"`
	Expiries      HourInfos `json:"expiries"`
	TotalOrphans  int       `json:"total_orphans"`
}

func (qi *QueueInfo) FormattedTotalExpiries() string {
	return printer.Sprintf("%d", qi.TotalExpiries)
}

func (qi *QueueInfo) FormattedTotalOrphans() string {
	return printer.Sprintf("%d", qi.TotalOrphans)
}

type QueueInfos []QueueInfo

func (s QueueInfos) Len() int {
	return len(s)
}

func (s QueueInfos) Less(i, j int) bool {
	return s[i].TotalExpiries > s[j].TotalExpiries
}

func (s QueueInfos) Swap(i, j int) {
	s[i], s[j] = s[j], s[i]
}

type HourInfo struct {
	Hour  int `json:"hour"`
	Count int `json:"count"`
}
type HourInfos []HourInfo

func (s HourInfos) Len() int {
	return len(s)
}

func (s HourInfos) Less(i, j int) bool {
	return s[i].Hour > s[j].Hour
}

func (s HourInfos) Swap(i, j int) {
	s[i], s[j] = s[j], s[i]
}

func (s *GCState) getQueueInfos() QueueInfos {
	l := make(QueueInfos, 0, len(s.expiries))
	for q, m := range s.expiries {
		i := QueueInfo{Queue: q, Expiries: make(HourInfos, 0, len(m)), TotalOrphans: s.orphans[q]}
		for h, c := range m {
			i.TotalExpiries += c
			i.Expiries = append(i.Expiries, HourInfo{Hour: h, Count: c})
		}
		sort.Sort(i.Expiries)
		l = append(l, i)
	}
	sort.Sort(l)
	return l
}

type GCInfo struct {
	Timestamp int64      `json:"timestamp"`
	Queues    QueueInfos `json:"queues"`
}

func (i *GCInfo) TimestampHuman() string {
	if i == nil {
		return "unknown"
	}
	return time.Unix(i.Timestamp, 0).Format(time.RFC1123)
}

func (s *GCState) storeQueueInfos(infos QueueInfos) {
	gcInfo := GCInfo{Timestamp: time.Now().Unix(), Queues: infos}
	data, err := json.Marshal(gcInfo)
	if err != nil {
		logError("could not encode gc info as json: %s", err)
		return
	}
	_, err = s.redis.Set("beetle:lastgc", data, 0).Result()
	if err != nil {
		logError("could not store GC information in redis: %s", err)
	}
	logInfo("updated GC information in dedup store")
}

func (s *GCState) dumpQueueInfos(infos QueueInfos) {
	logInfo("active keys in dedup store by queue")
	for _, i := range infos {
		printer.Println("---------------------------------------------------------------------------------")
		printer.Printf("%s: %d active (%d orphans)\n", i.Queue, i.TotalExpiries, i.TotalOrphans)
		printer.Println("---------------------------------------------------------------------------------")
		for _, hi := range i.Expiries {
			printer.Printf("%3dh: %5d\n", hi.Hour, hi.Count)
		}
	}
}

func (s *GCState) gcKey(key string, threshold uint64) (int64, error) {
	v, err := s.redis.Get(key).Result()
	if err != nil {
		if err == redis.Nil {
			logDebug("key not found: %s", key)
			return 0, nil
		}
		return 0, err
	}
	expires, err := strconv.ParseUint(v, 10, 64)
	if err != nil {
		return 0, err
	}
	if expires > threshold {
		t := time.Duration(expires-threshold+uint64(s.opts.GcThreshold)) * time.Second
		logDebug("key %s expires in %s", key, t)
		s.recordExpiryHour(key, t)
		return 0, err
	}
	t := time.Duration(threshold-expires) * time.Second
	logDebug("key %s has expired %s ago", key, t)
	msgID := s.msgId(key)
	keys := s.keys(msgID)
	// logDebug("deleting keys: %s", strings.Join(keys, ", "))
	n, err := s.redis.Del(keys...).Result()
	return n, err
}

func (s *GCState) maybeGcKey(key string, threshold uint64) (int64, error) {
	if strings.HasSuffix(key, ":expires") {
		return s.gcKey(key, uint64(threshold))
	}
	if strings.HasSuffix(key, ":status") {
		logDebug("skipping status key: %s", key)
		return 0, nil
	}
	msgID := s.msgId(key)
	expiresKey := s.key(msgID, "expires")
	_, err := s.redis.Get(expiresKey).Result()
	if err == redis.Nil {
		// this can happen for two reasons:
		// 1. we have real garbage
		// 2. the key has been deleted by a beetle subscriber
		// logDebug("key %s has no corresponding expires key: %s", key, expiresKey)
		n, err := s.redis.Del(key).Result()
		if err != nil {
			logError("could not delete potentially orphaned key '%s':%s", key, err)
		}
		queueName := s.msgQueueName(key)
		s.orphans[queueName] += int(n)
		return n, err
	}
	// logDebug("found expires key %s: %s", expiresKey, v)
	return 0, err
}

func (s *GCState) garbageCollectKeys(db int) bool {
	var total, expired int64
	defer func() { logInfo("expired %d keys out of %d in db %d", expired, total, db) }()
	ticker := time.NewTicker(1000 * time.Millisecond)
	threshold := time.Now().Unix() + int64(s.opts.GcThreshold)
	for range ticker.C {
		if interrupted {
			return false
		}
		if s.getMaster(db) {
			if s.cursor == 0 {
				logInfo("starting SCAN on db %d", db)
			}
			logDebug("s.cursor: %d", s.cursor)
			var err error
			var keys []string
			keys, s.cursor, err = s.redis.Scan(s.cursor, "msgid:*", 10000).Result()
			if err != nil {
				logError("starting over: %v", err)
				return true
			}
			logDebug("retrieved %d keys from db %d", len(keys), db)
			total += int64(len(keys))
			for _, key := range keys {
				if interrupted {
					return false
				}
				collected, err := s.maybeGcKey(key, uint64(threshold))
				if err != nil {
					logError("starting over: %v", err)
					return true
				}
				expired += collected
			}
			if s.cursor == 0 {
				return false
			}
		}
	}
	return false
}

func (s *GCState) garbageCollectKeysFromFile(db int, filePath string) {
	var total, expired int64
	defer func() { logInfo("expired %d keys out of %d potential keys in db %d", expired, total, db) }()

	file, err := os.Open(filePath)
	if err != nil {
		logError("%v", err)
		return
	}
	defer file.Close()

	s.getMaster(db)

	threshold := time.Now().Unix() + int64(s.opts.GcThreshold)
	re := regexp.MustCompile("^(msgid:[^:]+:[-0-9a-f]*):expires$")
	scanner := bufio.NewScanner(file)
	numKeySuffixes := int64(len(s.keySuffixes))
	for scanner.Scan() {
		if interrupted {
			break
		}
		line := scanner.Text()
		if !re.MatchString(line) {
			continue
		}
		total += numKeySuffixes
		collected, err := s.maybeGcKey(line, uint64(threshold))
		if err != nil {
			logError("could not collect %s: %v", line, err)
			continue
		}
		expired += collected
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
		s.cursor = 0
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
// successfully on all databases which need GC.
func RunGarbageCollectKeys(opts GCOptions) error {
	logDebug("garbage collecting keys with options: %+v", opts)
	state := &GCState{opts: opts}
	state.keySuffixes = []string{"status", "ack_count", "timeout", "delay", "attempts", "exceptions", "mutex", "expires"}
restart:
	state.resetExpiries()
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
			if opts.GcKeyFile == "" {
				restart := state.garbageCollectKeys(db)
				if restart {
					goto restart
				}
			} else {
				state.garbageCollectKeysFromFile(db, opts.GcKeyFile)
			}
		}
	}
	state.getMaster(0)
	if state.redis != nil {
		infos := state.getQueueInfos()
		state.storeQueueInfos(infos)
		state.dumpQueueInfos(infos)
	}
	return nil
}
