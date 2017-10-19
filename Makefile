export ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

PROJECT_NAME := device-dashboard

GIT_COMMIT   := $(shell git rev-parse --short HEAD)
GIT_DIRTY    := $(shell test -n "`git status --porcelain`" && echo "dirty" || echo "clean")
VERSION      ?= $(GIT_COMMIT)

DOCKER_SERVICE   := dev
DOCKER_COMPOSE   := $(shell which docker-compose)
DOCKER_SHELL     := $(DOCKER_COMPOSE) exec -T $(DOCKER_SERVICE) /bin/bash
DOCKER_SHELL_TTY := $(DOCKER_COMPOSE) exec $(DOCKER_SERVICE) /bin/bash

DOCKER_IMAGE_NAME := $(PROJECT_NAME)
DOCKER_REGISTRY   ?= 881638663441.dkr.ecr.us-east-1.amazonaws.com

DOCKER_TAG_LOCAL_VERSION  := $(DOCKER_IMAGE_NAME):$(VERSION)
DOCKER_TAG_LOCAL_LATEST   := $(DOCKER_IMAGE_NAME):latest
DOCKER_TAG_REMOTE_VERSION := $(DOCKER_REGISTRY)/$(DOCKER_TAG_LOCAL_VERSION)
DOCKER_TAG_REMOTE_LATEST  := $(DOCKER_REGISTRY)/$(DOCKER_TAG_LOCAL_LATEST)

.PHONY: help
help:
	@echo "help:      This help message"
	@echo "info:      Print environment information"
	@echo "up:        Create development environment"
	@echo "down:      Destroy development environment"
	@echo "shell:     Start a shell in the development environment"
	@echo "dev:       Start project within the development environment"
	@echo "dev-stop:  Stop project within the development environment"
	@echo "test:      Run all project tests. Results in JUnit test results"
	@echo "test-unit: Run all unit tests. Results in JUnit test results"
	@echo "create:    Create all build artifacts"
	@echo "clean:     Return working directory back to a clean state"
	@echo "package:   Package build artifacts in to docker images"
	@echo "run:       Run packaged artifact"
	@echo "publish:   Publish packaged artifacts to configured repository"
	@echo "deploy:    Deploy published artifacts to cluster"

.PHONY: info
info:
	@echo "Project:         $(PROJECT_NAME)"
	@echo "Version:         $(VERSION)"
	@echo "Git Commit:      $(GIT_COMMIT)"
	@echo "Git Tree State:  $(GIT_DIRTY)"
	@echo "Docker Image:    $(DOCKER_TAG_LOCAL_VERSION)"
	@echo "Docker Registry: $(DOCKER_REGISTRY)"

# Setup docker environment
.PHONY: up
up:
	$(DOCKER_COMPOSE) up -d

# Teardown docker environment
.PHONY: down
down:
	$(DOCKER_COMPOSE) down

# Create an interactive shell in environment
.PHONY: shell
shell: SHELL := $(DOCKER_SHELL_TTY)
shell:
	bash

.PHONY: dev
dev: deps dev-info dev-start
	@:

.PHONY: dev-info
dev-info:
	@echo "WARN: ################################################"
	@echo "WARN: CTRL^C will **NOT** stop the development server."
	@echo "WARN: Use 'make dev-stop' to stop the server process."
	@echo "WARN:"
	@echo "WARN: Make does not handle process signals well."
	@echo "WARN: ################################################"

.PHONY: dev-start
dev-start: SHELL := $(DOCKER_SHELL)
dev-start: deps dev-info dev-stop
	@echo "INFO: Starting development server"
	yarn start

.PHONY: dev-stop
dev-stop: SHELL := $(DOCKER_SHELL)
dev-stop:
	@echo "INFO: Stopping development server"
	@kill $$(pidof node) >/dev/null 2>&1 || true

# Run all tests
.PHONY: test
test: SHELL := $(DOCKER_SHELL)
test: deps test-unit

# Run test with junit reporter
.PHONY: test-unit
test-unit: SHELL := $(DOCKER_SHELL)
test-unit:
	CI=true yarn test
	@echo "Collect test results in to a predictable location"

# Build artifacts
.PHONY: build
build: SHELL := $(DOCKER_SHELL)
build: deps
	yarn build

# Clean source directory
.PHONY: clean
clean: SHELL := $(DOCKER_SHELL)
clean:
	rm -rf build
	rm -rf node_modules

# Package artifacts
.PHONY: package
package:
	docker build -t $(DOCKER_TAG_LOCAL_VERSION) -t $(DOCKER_TAG_LOCAL_LATEST) .

# Run the package
.PHONY: run
run:
	docker run --rm -it -p 8080:80 $(DOCKER_TAG_LOCAL_LATEST)

.PHONEY: deps
deps: SHELL := $(DOCKER_SHELL)
deps:
	yarn install

# Publish package
.PHONY: publish
publish: login
	docker tag $(DOCKER_TAG_LOCAL_LATEST) $(DOCKER_TAG_REMOTE_LATEST)
	docker tag $(DOCKER_TAG_LOCAL_VERSION) $(DOCKER_TAG_REMOTE_VERSION)
	docker push $(DOCKER_TAG_REMOTE_LATEST)
	docker push $(DOCKER_TAG_REMOTE_VERSION)

.PHONY: login
login:
	eval $$(aws ecr get-login)

.PHONY: deploy
deploy:
	kubectl set image deployment/$(PROJECT_NAME) $(PROJECT_NAME)=$(DOCKER_TAG_REMOTE_VERSION)
	kubectl rollout status -w deployment/$(PROJECT_NAME)
