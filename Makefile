SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: all check build lint test clean help

all: check

build:
	@chmod +x build.sh 2>/dev/null || true
	./build.sh

test:
	@chmod +x setup.sh build.sh tests/*.sh 2>/dev/null || true
	ALLOW_ROOT=$${ALLOW_ROOT:-true} bash ./tests/run_tests.sh

lint: build
	@command -v shellcheck >/dev/null 2>&1 || { echo "Error: shellcheck is not installed" >&2; exit 1; }
	shellcheck -x -e SC2329 build.sh setup.sh dist/setup.sh tests/*.sh

check: lint test

clean:
	@rm -rf dist /tmp/fedora-setup-* /tmp/fpi_backup_test_* /tmp/fpi_test_*

help:
	@echo "Available targets:"
	@echo "  make check  - Run ShellCheck and automated test suite (default)"
	@echo "  make build  - Assemble standalone script in dist/ via build.sh"
	@echo "  make lint   - Run ShellCheck across all scripts"
	@echo "  make test   - Run automated test suite"
	@echo "  make clean  - Clean temporary test artifacts"
	@echo "  make help   - Display this help message"

