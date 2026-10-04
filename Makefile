PYTHON ?= python3
SUITE ?= fast
FILE ?=
ARGS ?=

.PHONY: test-setup test-setup-kernel test test-lua test-python test-integration test-kernel test-all test-list

test-setup:
	$(PYTHON) scripts/setup-tests.py

test-setup-kernel:
	$(PYTHON) scripts/setup-tests.py --kernel

test:
	$(PYTHON) scripts/run-tests.py --suite $(SUITE) $(if $(FILE),--match "$(FILE)",) -- $(ARGS)

test-lua:
	$(PYTHON) scripts/run-tests.py --language lua --suite $(SUITE) $(if $(FILE),--match "$(FILE)",)

test-python:
	$(PYTHON) scripts/run-tests.py --language python --suite $(SUITE) $(if $(FILE),--match "$(FILE)",) -- $(ARGS)

test-integration:
	$(MAKE) test SUITE=integration

test-kernel:
	$(MAKE) test SUITE=kernel

test-all:
	$(MAKE) test SUITE=all

test-list:
	$(PYTHON) scripts/run-tests.py --suite all --list
