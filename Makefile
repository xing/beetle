.PHONY: all clean install uninstall test feature stats world release linux darwin

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
makefile_dir := $(patsubst %/,%,$(dir $(mkfile_path)))

BIN_DIR = $(makefile_dir)/bin
GO_PATH = $(makefile_dir)/go
GO_DEPS = \
	github.com/gorilla/websocket \
	github.com/jessevdk/go-flags \
	github.com/davecgh/go-spew/spew \
	gopkg.in/tylerb/graceful.v1 \
	gopkg.in/redis.v5

.godeps:
	$(GO_ENV) go get $(GO_DEPS)
	touch .godeps

GO_ENV = GOPATH=$(GO_PATH)
GO_PKG = github.com/xing/beetle
GO_SRC = go/src/$(GO_PKG)
GO_INSTALL_TARGETS = beetle
GO_TARGETS = $(GO_INSTALL_TARGETS) $(GO_NOINSTALL_TARGETS)

INSTALL_PROGRAM = ginstall
PLATFORM := $(shell uname -s)
ifeq ($(PLATFORM), Darwin)
  TAR := gnutar
else
  TAR := tar
endif

all: $(GO_TARGETS)

clean:
	rm -rf go/pkg go/bin $(GO_TARGETS) .godeps

install: $(GO_INSTALL_TARGETS)
	$(INSTALL_PROGRAM) beetle $(BIN_DIR)

uninstall:
	cd $(BIN_DIR) && rm -f $(GO_INSTALL_TARGETS)

GO_MODULES = $(patsubst %,$(GO_SRC)/%, client.go server.go redis.go redis_shim.go redis_server_info.go logging.go version.go)

beetle: $(GO_SRC)/beetle.go $(GO_MODULES) .godeps
	$(GO_ENV) go build -o $@ $< $(GO_MODULES)

test:
	cd go/src/$(GO_PKG) && $(GO_ENV) go test

feature:
	cucumber features/redis_auto_failover.feature:9

stats:
	cloc --exclude-dir=coverage lib test features go/src/github.com/xing

world:
	test `uname -s` = Darwin && $(MAKE) linux darwin || $(MAKE) darwin linux

BEETLE_VERSION := v$(shell awk '/^const BEETLE_VERSION =/ { gsub(/"/, ""); print $$4}'  $(GO_SRC)/version.go)

release:
	@test "$(shell git status --porcelain)" = "" || (echo "project is dirty, please check in modified files and remove untracked ones" && false)
	@git fetch --tags xing
	@test "`git tag -l | grep $(BEETLE_VERSION)`" != "\n" || (echo "version $(BEETLE_VERSION) already exists. please edit version/version.go" && false)
	@$(MAKE) world
	@./create_release.sh
	@git fetch --tags xing

linux:
	GOOS=linux GOARCH=amd64 $(MAKE) clean all
	rm -f release/beetle* release/linux.tar.gz
	cp -p $(GO_INSTALL_TARGETS) release/
	cd release && $(TAR) czf linux.tar.gz beetle*
	rm -f release/beetle*

darwin:
	GOOS=darwin GOARCH=amd64 $(MAKE) clean all
	rm -f release/beetle* release/darwin.tar.gz
	cp -p $(GO_INSTALL_TARGETS) release/
	cd release && $(TAR) czf darwin.tar.gz beetle*
	rm -f release/beetle*
