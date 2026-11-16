SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: all check build build-check lint test clean help

all: check

build:
	@chmod +x build.sh 2>/dev/null || true
	./build.sh

build-check:
	@chmod +x build.sh 2>/dev/null || true
	./build.sh --check

test:
	@chmod +x setup.sh build.sh tests/*.sh 2>/dev/null || true
	bash ./tests/run_tests.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "Error: shellcheck is not installed" >&2; exit 1; }
	shellcheck -e SC2329 build.sh setup.sh tests/*.sh

check: build-check lint test

clean:
	@rm -rf /tmp/fedora-setup-* /tmp/fpi_backup_test_* /tmp/fpi_test_*

help:
	@echo "Available targets:"
	@echo "  make check       - Verify build sync, ShellCheck, and test suite (default)"
	@echo "  make build       - Assemble setup.sh from src/ modules"
	@echo "  make build-check - Verify setup.sh is in sync with src/ modules"
	@echo "  make lint        - Run ShellCheck across all scripts"
	@echo "  make test        - Run automated test suite"
	@echo "  make clean       - Clean temporary test artifacts"
	@echo "  make help        - Display this help message"

