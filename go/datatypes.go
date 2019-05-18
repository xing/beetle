package main

import (
	"sort"
	"time"
)

// StringChannel is a channel for strings.
type StringChannel chan string

// ChannelMap maps client ids to string channels.
type ChannelMap map[string]StringChannel

// ChannelSet is a set of StringChannels.
type ChannelSet map[StringChannel]StringChannel

// StringList implements convenience functions on string slices.
type StringList []string

// Include check whether a given string s is included in string slice l.
func (l *StringList) Include(s string) bool {
	for _, x := range *l {
		if x == s {
			return true
		}
	}
	return false
}

// Add adds a given string s to the end of string slice l.
func (l *StringList) Add(s string) {
	if (*l).Include(s) {
		return
	}
	*l = append(*l, s)
}

// StringSet implements convenient set abstractions.
type StringSet map[string]bool

// Keys returns the keys of a StringSet as a sorted string slice.
func (l *StringSet) Keys() []string {
	keys := make([]string, 0, len(*l))
	for k := range *l {
		keys = append(keys, k)
	}
	sort.Sort(sort.StringSlice(keys))
	return keys
}

// Include checks whether a given string s is in the set l.
func (l *StringSet) Include(s string) bool {
	_, ok := (*l)[s]
	return ok
}

// Add adds a string s to stringset l.
func (l *StringSet) Add(s string) {
	if !l.Include(s) {
		(*l)[s] = true
	}
}

// Equals checks whether two string sets are equal.
func (l StringSet) Equals(s StringSet) bool {
	if len(l) != len(s) {
		return false
	}
	for x := range l {
		if !s.Include(x) {
			return false
		}
	}
	return true
}

// Intersect computes the intersection of two string sets
func (l StringSet) Intersect(r StringSet) StringSet {
	intersection := make(StringSet)
	for s := range l {
		if r[s] {
			intersection[s] = true
		}
	}
	return intersection
}

// TimeSet maps client ids to last seen times.
type TimeSet map[string]time.Time

// Equal checks whether two timesets are identical.
func (s1 TimeSet) Equal(s2 TimeSet) bool {
	if len(s1) != len(s2) {
		return false
	}
	for k, v := range s1 {
		if !v.Equal(s2[k]) {
			return false
		}
	}
	return true
}
