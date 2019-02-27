package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"regexp"
	"sort"
	"strings"
)

// MasterFileExists checks whether the give path exists on disk.
func MasterFileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// RedisMastersFromMasterFile creates a map of system names to redis
// address strings from the given file path. Returns the empty map if
// the file does not exist or is empty.
func RedisMastersFromMasterFile(path string) map[string]string {
	s := ReadRedisMasterFile(path)
	return UnmarshalMasterFileContent(s)
}

// UnmarshalMasterFileContent parses masterfile content.
func UnmarshalMasterFileContent(s string) map[string]string {
	m := make(map[string]string, 0)
	for _, line := range strings.Split(s, "\n") {
		if line == "" {
			continue
		}
		if strings.Contains(line, "/") {
			parts := strings.SplitN(line, "/", 2)
			m[parts[0]] = parts[1]
		} else {
			m["system"] = line
		}
	}
	return m
}

// MarshalMasterFileContent converts a system to master map into a
// string. Keys are sorted lexicographically.
func MarshalMasterFileContent(masters map[string]string) string {
	s := ""
	keys := make([]string, 0)
	for k := range masters {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if len(keys) == 1 && keys[0] == "system" {
		return masters["system"]
	}
	for _, name := range keys {
		server := masters[name]
		s += name + "/" + server + "\n"
	}
	return s
}

// ClearRedisMasterFile removes the entry for the given system from
// the file at the given path.
func ClearRedisMasterFile(path string) error {
	return WriteRedisMasterFile(path, "")
}

// ReadRedisMasterFile reads the file at the given path, stripping a
// potential newline from the last line read.
func ReadRedisMasterFile(path string) string {
	b, err := ioutil.ReadFile(path)
	if err != nil {
		logError("could not read redis master file '%s': %v", path, err)
		return ""
	}
	return strings.TrimRight(string(b), "\n")
}

// WriteRedisMasterFile writes given string into file at given path, creating it
// if necessary. Returns an error if the file cannot be created.
func WriteRedisMasterFile(path string, content string) error {
	trimmed := strings.TrimRight(content, "\n")
	escaped := strings.Replace(trimmed, "\n", "\\n", -1)
	logInfo("writing '%s' to redis master file '%s'", escaped, path)
	f, err := os.Create(path)
	if err != nil {
		logError("could not create master file '%s': %s", path, err)
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, strings.NewReader(trimmed))
	if err != nil {
		logError("could not write master file '%s': %s", path, err)
		return err
	}
	return nil
}

// VerifyMasterFileString checks that the given path does not look like a
// server:port combination.
func VerifyMasterFileString(path string) error {
	matched, err := regexp.MatchString("^[0-9a-z.]+:[0-9]+$", path)
	if err != nil {
		return err
	}
	if matched {
		return fmt.Errorf("redis_server config option must point to a file: %s", path)
	}
	return nil
}
