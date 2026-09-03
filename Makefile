.PHONY: all test lint check

all: check

test:
	./tests/run_tests.sh

lint:
	shellcheck -e SC1091 setup.sh tests/*.sh

check: lint test
