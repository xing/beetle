package main

import (
	"testing"
)

func TestKeyExtraction(t *testing.T) {
	key := "msgid:schubbel_dibubbel:dacf135b-35ec-4326-a9e3-e1ffcaf3286e:expires"
	var s *GCState = nil
	msgId := s.msgId(key)
	if msgId != "msgid:schubbel_dibubbel:dacf135b-35ec-4326-a9e3-e1ffcaf3286e" {
		t.Errorf("could not extract message id: %s", msgId)
	}
}
