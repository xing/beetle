package main

import (
	"os"
	"testing"
)

func TestRedisIsMaster(t *testing.T) {
	r := NewRedisShim("127.0.0.1:7001")
	isMaster := r.IsMaster()
	if !isMaster {
		t.Errorf("current redis is not a master")
	}
}

func TestReadMasterFile(t *testing.T) {
	path := "/tmp/test_redis_read_master_file.txt"
	if err := WriteRedisMasterFile(path, "127.0.0.1:7001"); err != nil {
		t.Errorf("%s", err)
	}
	defer os.Remove(path)
	s := ReadRedisMasterFile(path)
	if s != "127.0.0.1:7001" {
		t.Errorf("reading master file failed: %s != %s", s, "127.0.0.1:7001")
	}
}

func TestRedisIsAvailable(t *testing.T) {
	r := NewRedisShim("127.0.0.1:7001")
	isAvailable := r.IsAvailable()
	if !isAvailable {
		t.Errorf("current redis is not available, but should be")
	}
}

func TestRedisNotAvailable(t *testing.T) {
	r := NewRedisShim("127.0.0.1:7003")
	isAvailable := r.IsAvailable()
	if isAvailable {
		t.Errorf("current redis is available, but should not be")
	}
}

func TestRedisMakeMaster(t *testing.T) {
	r := NewRedisShim("127.0.0.1:7001")
	err := r.MakeMaster()
	if err != nil {
		t.Errorf("current redis could not be made master: %s", err)
	}
	if !r.IsMaster() {
		t.Errorf("current redis could not be made master")
	}
}

func TestRedisIsSlaveOf(t *testing.T) {
	r := NewRedisShim("127.0.0.1:7002")
	if !r.IsSlaveOf("127.0.0.1", 7001) {
		t.Errorf("redis should be slave")
	}
}
