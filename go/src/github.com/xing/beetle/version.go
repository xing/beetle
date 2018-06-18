package main

import (
	"fmt"
	"os"
)

// BEETLE_VERSION is displayed in the web UI and can be checked using beetle --version.
const BEETLE_VERSION = "2.1.2"

// ReportVersionIfRequestedAndExit checks os.Args for the string --version,
// prints the version if found and then exits.
func ReportVersionIfRequestedAndExit() {
	for _, a := range os.Args {
		if a == "--version" {
			fmt.Println(BEETLE_VERSION)
			os.Exit(1)
		}
	}
}
