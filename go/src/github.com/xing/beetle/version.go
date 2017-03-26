package main

import (
	"fmt"
	"os"
)

const BEETLE_VERSION = "1.1"

func ReportVersionIfRequestedAndExit() {
	for _, a := range os.Args {
		if a == "--version" {
			fmt.Println(BEETLE_VERSION)
			os.Exit(1)
		}
	}
}
