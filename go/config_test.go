package main

import (
	"fmt"
	"testing"
)

func TestCanGetFailoverSetsFromConfig(t *testing.T) {
	fmt.Println("=== CanGetFailoverSetsFromConfig =================================")
	c := Config{RedisServers: "a.xxx.com:6379,b.xxx.com:6379"}
	expected := []FailoverSet{{name: "system", spec: "a.xxx.com:6379,b.xxx.com:6379"}}
	actual := c.FailoverSets()
	checkEqual(t, actual, expected)

	c = Config{RedisServers: "s1/a.xxx.com:6379,b.xxx.com:6379\ns2/a.yyy.com:6379,b.yyy.com:6379"}
	expected = []FailoverSet{{name: "s1", spec: "a.xxx.com:6379,b.xxx.com:6379"}, {name: "s2", spec: "a.yyy.com:6379,b.yyy.com:6379"}}
	actual = c.FailoverSets()
	checkEqual(t, actual, expected)
}
