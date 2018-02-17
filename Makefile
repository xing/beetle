.PHONY: all clean realclean install uninstall test test-main test-server test-consul feature stats world release linux darwin container tag push lint

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
makefile_dir := $(patsubst %/,%,$(dir $(mkfile_path)))

BIN_DIR = $(makefile_dir)/bin
GO_PATH = $(makefile_dir)/go
GO_DEPS = \
	github.com/jessevdk/go-flags \
	github.com/pkg/errors \
	gopkg.in/gorilla/websocket.v1 \
	gopkg.in/redis.v5 \
	gopkg.in/tylerb/graceful.v1 \
	gopkg.in/yaml.v2

# the following dependencies cause go get to return an error code
EXTRA_DEPS = \
	github.com/davecgh/go-spew

.godeps:
	git submodule init
	git submodule update
	-$(GO_ENV) go get $(EXTRA_DEPS)
	$(GO_ENV) go get $(GO_DEPS)
	touch .godeps

GO_ENV = GOPATH=$(GO_PATH) V=$(V)
GO_PKG = github.com/xing/beetle
GO_SRC = go/src/$(GO_PKG)
GO_INSTALL_TARGETS = beetle
GO_TARGETS = $(GO_INSTALL_TARGETS) $(GO_NOINSTALL_TARGETS)
SCRIPTS =

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

realclean: clean
	rm -rf $(patsubst %,go/src/%,$(GO_DEPS) $(EXTRA_DEPS))

install: $(GO_INSTALL_TARGETS)
	$(INSTALL_PROGRAM) $(GO_INSTALL_TARGETS) $(SCRIPTS) $(BIN_DIR)

uninstall:
	cd $(BIN_DIR) && rm -f $(GO_INSTALL_TARGETS) $(SCRIPTS)

GO_MODULES = $(patsubst %,$(GO_SRC)/%, client.go server.go redis.go redis_shim.go redis_server_info.go logging.go version.go garbage_collect_keys.go notification_mailer.go config.go)

beetle: $(GO_SRC)/beetle.go $(GO_MODULES) .godeps
	$(GO_ENV) go build -o $@ $< $(GO_MODULES)

test: test-main test-server test-consul

test-main:
	cd go/src/$(GO_PKG) && $(GO_ENV) go test

test-server:
	cd go/src/$(GO_PKG) && $(GO_ENV) go test -run TestServer

test-consul:
	cd go/src/$(GO_PKG)/consul && $(GO_ENV) go test

lint:
	@golint -min_confidence 1.0 $(GO_SRC)/*.go
	@cd $(GO_SRC)/consul && golint -min_confidence 1.0 *.go

feature:
	cucumber features/redis_auto_failover.feature:9

stats:
	cloc --exclude-dir=coverage,vendor lib test features go/src/github.com/xing

world:
	test `uname -s` = Darwin && $(MAKE) linux container tag push darwin || $(MAKE) darwin linux container tag push

BEETLE_VERSION := v$(shell awk '/^const BEETLE_VERSION =/ { gsub(/"/, ""); print $$4}'  $(GO_SRC)/version.go)
TAG ?= latest

release:
	@test "$(shell git status --porcelain)" = "" || test "$(FORCE)" == "1" || (echo "project is dirty, please check in modified files and remove untracked ones (or use FORCE=1)" && false)
	@git fetch --tags
	@test "`git tag -l | grep $(BEETLE_VERSION)`" != "\n" || (echo "version $(BEETLE_VERSION) already exists. please edit version/version.go" && false)
	@$(MAKE) world
	@./create_release.sh
	@git fetch --tags

linux:
	GOOS=linux GOARCH=amd64 $(MAKE) clean all
	rm -f release/beetle* release/linux.tar.gz
	cp -p $(GO_INSTALL_TARGETS) $(SCRIPTS) release/
	cd release && $(TAR) czf linux.tar.gz beetle*
	rm -f release/beetle*

darwin:
	GOOS=darwin GOARCH=amd64 $(MAKE) clean all
	rm -f release/beetle* release/darwin.tar.gz
	cp -p $(GO_INSTALL_TARGETS) $(SCRIPTS) release/
	cd release && $(TAR) czf darwin.tar.gz beetle*
	rm -f release/beetle*

container:
	docker build -f Dockerfile -t=xingarchitects/gobeetle .

tag:
	docker tag xingarchitects/gobeetle xingarchitects/gobeetle:$(TAG)

push:
	docker push xingarchitects/gobeetle:$(TAG)
