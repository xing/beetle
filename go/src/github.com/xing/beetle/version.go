package main

import (
	"fmt"
	"os"
)

const BEETLE_VERSION = "2.0.0"

func ReportVersionIfRequestedAndExit() {
	for _, a := range os.Args {
		if a == "--version" {
			fmt.Println(BEETLE_VERSION)
			os.Exit(1)
		}
	}
}
