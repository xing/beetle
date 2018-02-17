package main

import (
	"fmt"
	"os"
)

// BEETLE_VERSION is displayed in the web UI and can be checke using beetle --version.
const BEETLE_VERSION = "2.0.2"

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
