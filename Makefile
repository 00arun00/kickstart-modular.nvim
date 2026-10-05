SUITE ?= fast
FILE ?=
ARGS ?=
TEST_PYTHON = .test-venv/bin/python
MARKERS = $(if $(filter all,$(SUITE)),not manual,$(SUITE))$(if $(LANGUAGE), and $(LANGUAGE),)

.PHONY: test-setup test-setup-kernel test test-lua test-python test-integration test-kernel test-all test-list

test-setup:
	UV_PROJECT_ENVIRONMENT=.test-venv uv sync --locked --only-group test

test-setup-kernel:
	UV_PROJECT_ENVIRONMENT=.test-kernel uv sync --locked --only-group kernel

test:
	PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 $(TEST_PYTHON) -m pytest -m "$(MARKERS)" $(if $(FILE),-k "$(FILE)",) $(ARGS)

test-lua: LANGUAGE = lua
test-lua: test

test-python: LANGUAGE = python
test-python: test

test-integration:
	$(MAKE) test SUITE=integration

test-kernel:
	$(MAKE) test SUITE=kernel

test-all:
	$(MAKE) test SUITE=all

test-list:
	$(MAKE) test SUITE=all ARGS=--collect-only
