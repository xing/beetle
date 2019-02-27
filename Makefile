.PHONY: all clean realclean install uninstall test test-main test-server test-consul feature1 feature2 feature3 stats world release linux darwin container tag push lint tidy

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
makefile_dir := $(patsubst %/,%,$(dir $(mkfile_path)))

BIN_DIR = $(makefile_dir)/bin
GO_PATH = $(makefile_dir)/go

export GO11MODULE=on

GO_ENV = V=$(V)
GO_SRC = go
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
	cd $(GO_SRC) && packr clean
	rm -rf go/pkg go/bin $(GO_TARGETS)

tidy:
	cd $(GO_SRC) && go mod tidy

realclean: clean
	rm .packr
	cd $(GO_SRC) && go clean -modcache

install: $(GO_INSTALL_TARGETS)
	$(INSTALL_PROGRAM) $(GO_INSTALL_TARGETS) $(SCRIPTS) $(BIN_DIR)

uninstall:
	cd $(BIN_DIR) && rm -f $(GO_INSTALL_TARGETS) $(SCRIPTS)

GO_MODULES = $(patsubst %,$(GO_SRC)/%, client.go server.go redis.go redis_shim.go redis_server_info.go logging.go version.go garbage_collect_keys.go notification_mailer.go config.go)

.packr:
	go get github.com/gobuffalo/packr/packr
	touch .packr

$(GO_SRC)/a_main-packr.go: $(GO_SRC)/templates/index.html .packr
	cd $(GO_SRC) && packr

beetle: $(GO_SRC)/beetle.go $(GO_MODULES) $(GO_SRC)/a_main-packr.go
	cd $(GO_SRC) && $(GO_ENV) go build -o ../$@

test: test-main test-server

test-main:
	cd $(GO_SRC) && go test

test-server:
	cd $(GO_SRC) && $(GO_ENV) go test -run TestServer

test-consul:
	cd $(GO_SRC)/consul && $(GO_ENV) go test

lint:
	@cd $(GO_SRC) && golint -min_confidence 1.0 *.go
	@cd $(GO_SRC)/consul && golint -min_confidence 1.0 *.go

feature1:
	cucumber features/redis_auto_failover.feature:9

feature2:
	cucumber features/redis_auto_failover.feature:26

feature3:
	cucumber features/redis_auto_failover.feature:48

stats:
	cloc --exclude-dir=coverage,vendor lib test features $(GO_SRC)

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
