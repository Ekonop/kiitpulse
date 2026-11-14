# KIITPulse — common tasks.
#
#   make test     run every test suite (Go, Dart packages, Flutter)
#   make check    analyze + test everything, the same gate CI runs
#   make run      start the backend against local Redis
#   make demo     run the Flutter app against the in-memory simulation
#
# No external task runner is required; plain make is enough and is already on
# every machine that has a Go or Flutter toolchain.

SHELL := /bin/bash
.DEFAULT_GOAL := help

FLUTTER ?= flutter
DART    ?= dart
GO      ?= go
MOBILE  := apps/mobile
API     := packages/kiit_api_client
CONTRACTS := packages/kiit_contracts
UI      := packages/kiit_ui
BACKEND := services/backend

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- backend

.PHONY: test-go
test-go: ## Go tests with the race detector
	cd $(BACKEND) && $(GO) test -race ./...

.PHONY: build-go
build-go: ## Compile the backend
	cd $(BACKEND) && $(GO) build ./...

.PHONY: run
run: ## Run the backend against local Redis
	@test -n "$$KIITPULSE_JWT_SECRET" || \
		echo "note: KIITPULSE_JWT_SECRET unset; set it to >=32 bytes"
	cd $(BACKEND) && $(GO) run .

# ---------------------------------------------------------------- dart

.PHONY: test-dart
test-dart: ## API client + contracts tests
	cd $(API) && $(DART) test
	cd $(CONTRACTS) && $(DART) test

.PHONY: test-flutter
test-flutter: ## Widget tests for the app
	cd $(MOBILE) && $(FLUTTER) test

.PHONY: analyze
analyze: ## Static analysis across all Dart code
	cd $(CONTRACTS) && $(DART) analyze --fatal-infos
	cd $(UI) && $(FLUTTER) analyze --fatal-infos
	cd $(API) && $(DART) analyze --fatal-infos
	cd $(MOBILE) && $(FLUTTER) analyze --fatal-infos

# ---------------------------------------------------------------- aggregate

.PHONY: test
test: test-go test-dart test-flutter ## Every test suite
	@echo "all suites passed"

.PHONY: check
check: analyze test ## The gate CI runs: analyze + all tests

# ---------------------------------------------------------------- app

.PHONY: demo
demo: ## Run the app against the in-memory campus (no services needed)
	cd $(MOBILE) && $(FLUTTER) run \
		--dart-define=PULSE_BACKEND=demo

.PHONY: live
live: ## Run the app against a local backend
	cd $(MOBILE) && $(FLUTTER) run \
		--dart-define=PULSE_BACKEND=live \
		--dart-define=PULSE_API_URL=http://127.0.0.1:8080

.PHONY: apk
apk: ## Debug APK for a device
	cd $(MOBILE) && $(FLUTTER) build apk --debug

# ---------------------------------------------------------------- infra

.PHONY: up
up: ## Start Redis + Postgres + backend in Docker
	docker compose -f infra/docker-compose.yml up --build

.PHONY: down
down: ## Stop the local stack
	docker compose -f infra/docker-compose.yml down

.PHONY: clean
clean: ## Remove build artefacts
	cd $(MOBILE) && $(FLUTTER) clean
	cd $(BACKEND) && $(GO) clean -cache -testcache 2>/dev/null || true
