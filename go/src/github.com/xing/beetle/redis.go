package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"regexp"
	"strings"
)

func MasterFileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func RedisMasterFromMasterFile(path string) *RedisShim {
	s := ReadRedisMasterFile(path)
	if s == "" {
		return nil
	}
	return NewRedisShim(s)
}

func ClearRedisMasterFile(path string) error {
	return WriteRedisMasterFile(path, "")
}

func ReadRedisMasterFile(path string) string {
	b, err := ioutil.ReadFile(path)
	if err != nil {
		logError("could not read redis master file '%s': %v", path, err)
		return ""
	}
	return strings.TrimRight(string(b), "\n")
}

func WriteRedisMasterFile(path string, content string) error {
	logInfo("writing '%s' to redis master file '%s'", content, path)
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, strings.NewReader(content))
	if err != nil {
		return err
	}
	return nil
}

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
