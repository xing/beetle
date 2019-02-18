// Copyright (c) 2012 Moritz Bitsch
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// Package daemonize provides the Daemonize method which allows a go program to run
// as a unix daemon
package daemonize

import (
	"github.com/yookoala/realpath"
	"os"
	"syscall"
)

// Detach from controling terminal and run in the background as system daemon.
//
// Unless nochdir is true Daemonize changes the current working
// directory to "/".
//
// Unless noclose is true Daemonize redirects os.Stdin, os.Stdout and
// os.Stderr to "/dev/null"
func Daemonize(nochdir, noclose bool) (*os.Process, error) {
	daemonizeState := os.Getenv("_GOLANG_DAEMONIZE_FLAG")
	switch daemonizeState {
	case "":
		syscall.Umask(0)
		os.Setenv("_GOLANG_DAEMONIZE_FLAG", "1")
	case "1":
		syscall.Setsid()
		os.Setenv("_GOLANG_DAEMONIZE_FLAG", "2")
	case "2":
		os.Setenv("_GOLANG_DAEMONIZE_FLAG", "")
		return nil, nil
	}

	var attrs os.ProcAttr

	if !nochdir {
		attrs.Dir = "/"
	}

	if noclose {
		attrs.Files = []*os.File{os.Stdin, os.Stdout, os.Stderr}
	} else {
		f, err := os.Open("/dev/null")
		if err != nil {
			return nil, err
		}
		attrs.Files = []*os.File{f, f, f}
	}

	exe, err := realpath.Realpath(os.Args[0])
	if err != nil {
		return nil, err
	}

	p, err := os.StartProcess(exe, os.Args, &attrs)
	if err != nil {
		return nil, err
	}

	return p, nil
}
