package main

import (
	"fmt"
	"os"
	"testing"
)

func TestRedisIsMaster(t *testing.T) {
	fmt.Println("=== RedisIsMaster ================================================")
	r := NewRedisShim("127.0.0.1:6379")
	isMaster := r.IsMaster()
	if !isMaster {
		t.Errorf("current redis is not a master")
	}
}

func TestReadMasterFile(t *testing.T) {
	fmt.Println("=== ReadMasterFile ===============================================")
	path := "/tmp/test_redis_read_master_file.txt"
	if err := WriteRedisMasterFile(path, "127.0.0.1:6379"); err != nil {
		t.Errorf("%s", err)
	}
	defer os.Remove(path)
	s := ReadRedisMasterFile(path)
	if s != "127.0.0.1:6379" {
		t.Errorf("reading master file failed: %s != %s", s, "127.0.0.1:6379")
	}
}

func TestRedisIsAvailable(t *testing.T) {
	fmt.Println("=== ReadIsAvailable ===============================================")
	r := NewRedisShim("127.0.0.1:6379")
	isAvailable := r.IsAvailable()
	if !isAvailable {
		t.Errorf("current redis is not available, but should be")
	}
}

func TestRedisNotAvailable(t *testing.T) {
	fmt.Println("=== ReadIsNotAvailable ============================================")
	r := NewRedisShim("127.0.0.1:6377")
	isAvailable := r.IsAvailable()
	if isAvailable {
		t.Errorf("current redis is available, but should not be")
	}
}

func TestRedisMakeMaster(t *testing.T) {
	fmt.Println("=== RedisMakeMaster ===============================================")
	r := NewRedisShim("127.0.0.1:6379")
	err := r.MakeMaster()
	if err != nil {
		t.Errorf("current redis could not be made master: %s", err)
	}
	if !r.IsMaster() {
		t.Errorf("current redis could not be made master")
	}
}

func TestRedisIsSlaveOf(t *testing.T) {
	fmt.Println("=== RedisIsSlaveOf ===============================================")
	r := NewRedisShim("127.0.0.1:6380")
	if !r.IsSlaveOf("127.0.0.1", 6379) {
		t.Errorf("redis should be slave")
	}
}
