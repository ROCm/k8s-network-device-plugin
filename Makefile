#
# Credit:
#   This makefile was adapted from: https://github.com/vincentbernat/hellogopher/blob/feature/glide/Makefile
#
# Go environment

# Import development related environment variables from dev.env
ifneq ("$(wildcard dev.env)","")
    include dev.env
endif

PROJECT_VERSION ?= v1.2.0

# Go toolchain for Dockerfile.build and the images/Dockerfile builder stage.
# Must match go.mod and the ARG default in both Dockerfiles - see
# check-golang-version.
GOLANG_VERSION ?= 1.25.8

export GOPATH?=$(shell go env GOPATH)
BINDIR=$(CURDIR)/bin
# Build info
BINARY_NAME=sriovdp
BUILDDIR=$(CURDIR)/build
PKGS = $(or $(PKG),$(shell go list ./... | grep -v ".*/mocks"))
# Test artifacts and settings
TIMEOUT = 15
COVERAGE_DIR = $(CURDIR)/test/coverage
COVERAGE_MODE = atomic
COVERAGE_PROFILE = $(COVERAGE_DIR)/cover.out
# Docker image
DOCKERFILE?=$(CURDIR)/images/Dockerfile
DOCKER_REGISTRY ?= docker.io/rocm
IMAGE_NAME ?= k8s-network-device-plugin
IMAGE_TAG_BASE ?= $(DOCKER_REGISTRY)/$(IMAGE_NAME)
IMAGE_TAG ?= $(PROJECT_VERSION)
IMG ?= $(IMAGE_TAG_BASE):$(IMAGE_TAG)

IMG_FILE_NAME ?= $(IMAGE_NAME)-$(IMAGE_TAG)
IMG_DIR=$(BUILDDIR)/docker
DIRS=$(BINDIR) $(BUILDDIR) $(COVERAGE_DIR) $(IMG_DIR) 

HELM_CHART_DIR ?= $(CURDIR)/helm-charts-k8s
HELM_CHART_VERSION ?= $(PROJECT_VERSION)
HELM_CHART_APP_VERSION ?= $(IMAGE_TAG)
HELM_CHART_NAME ?= network-device-plugin-charts
HELM_RELEASE_NAME ?= amd-network-device-plugin
HELM_RELEASE_NAMESPACE ?= kube-amd-network
HELM_OUTPUT_FILE_PREFIX ?= k8s-network-device-plugin-helm-k8s
HELM_OUTPUT_FILE_NAME ?= $(HELM_OUTPUT_FILE_PREFIX)-$(PROJECT_VERSION).tgz
CHART_DEST ?= $(HELM_CHART_DIR)/$(HELM_OUTPUT_FILE_NAME)

# Local build container image; never pushed or pulled. The tag tracks
# GOLANG_VERSION so a Go bump does not reuse a stale image.
DOCKER_BUILDER_TAG := $(GOLANG_VERSION)
DOCKER_BUILDER_IMAGE ?= k8s-network-device-plugin-build:$(DOCKER_BUILDER_TAG)
BUILD_BASE_IMG ?= golang:$(GOLANG_VERSION)
CONTAINER_WORKDIR := /k8s-network-device-plugin

# Docker arguments - To pass proxy for Docker invoke it as 'make image HTTP_POXY=http://192.168.0.1:8080'
DOCKERARGS=
ifdef HTTP_PROXY
	DOCKERARGS += --build-arg http_proxy=$(HTTP_PROXY)
endif
ifdef HTTPS_PROXY
	DOCKERARGS += --build-arg https_proxy=$(HTTPS_PROXY)
endif

GO_BUILD_OPTS ?=
GO_LDFLAGS ?=
GO_FLAGS ?=
GO_TAGS ?=-tags no_openssl

ifdef STATIC
	GO_BUILD_OPTS+= CGO_ENABLED=0
	GO_LDFLAGS+= -extldflags \"-static\"
	GO_FLAGS+= -a
endif

V = 0
Q = $(if $(filter 1,$V),,@)

# go-get-tool will 'go install' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin GOFLAGS=-mod=mod go install $(2);\
}
endef

.PHONY: default
default: docker-lint docker-build docker-test ## Quick start - lint, build and test in the build container

.PHONY: all
all: lint build test

# Targets with a containerized twin: `make docker-test` runs `make test` inside
# $(DOCKER_BUILDER_IMAGE). `image` is excluded; it needs a Docker daemon and
# runs on the host.
CONTAINER_TARGETS := build test test-race test-coverage lint fmt mod helm copyrights generate-mocks
DOCKER_TARGETS := $(patsubst %,docker-%,$(CONTAINER_TARGETS))
.PHONY: $(DOCKER_TARGETS)

# Go caches, on a host directory owned by the invoking user. Must stay outside
# the source tree: the module cache holds thousands of .go files, which `lint`
# and tools/build/copyright would otherwise walk.
BUILD_CACHE_DIR ?= $(HOME)/.cache/k8s-network-device-plugin
CONTAINER_CACHE := /cache

$(DOCKER_TARGETS): docker-%: docker-build-env
	@echo "Running 'make $(*)' in container $(DOCKER_BUILDER_IMAGE)"
	$Q mkdir -p $(BUILD_CACHE_DIR)
	$Q docker run --rm \
		-e HOME=$(CONTAINER_CACHE) \
		-e GOCACHE=$(CONTAINER_CACHE)/go \
		-e GOPATH=$(CONTAINER_CACHE)/gopath \
		-e GOFLAGS=-mod=vendor \
		-v $(CURDIR):$(CONTAINER_WORKDIR) \
		-v $(BUILD_CACHE_DIR):$(CONTAINER_CACHE) \
		--user $(shell id -u):$(shell id -g) \
		-w $(CONTAINER_WORKDIR) \
		$(DOCKER_BUILDER_IMAGE) \
		make $(*)

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: mod
mod: ## Run go mod tidy and go mod edit to set up the go mod packages.
	@echo "setting up go mod packages"
	@go mod tidy
	#CVE-2026-33186
	@go mod edit -replace google.golang.org/grpc@v1.69.2=google.golang.org/grpc@v1.79.3
	@go mod tidy
	@go mod vendor

.PHONY: create-dirs
create-dirs: $(DIRS)

$(DIRS): ; $(info Creating directory $@...)
	$Q mkdir -p $@

# Verify one Go version across four places: go.mod, GOLANG_VERSION above, and the
# ARG default in each Dockerfile. The ARG defaults are what image-push-*.yml
# build with, since docker/build-push-action passes no build-args.
# Run by the Go Version Check job in build-test-lint.yml. Requires no Go.
.PHONY: check-golang-version
check-golang-version: ## Verify the Go version pins all agree
	$Q fail=0; \
	for spec in "go.mod:^go :2" "images/Dockerfile:^ARG GOLANG_VERSION=:2" "Dockerfile.build:^ARG GOLANG_VERSION=:2"; do \
		file=$${spec%%:*}; rest=$${spec#*:}; pat=$${rest%:*}; \
		got=$$(grep -m1 -E "$$pat" "$$file" | tr '= ' '\n\n' | tail -1); \
		if [ "$$got" != "$(GOLANG_VERSION)" ]; then \
			echo "  $$file says '$$got', GOLANG_VERSION is '$(GOLANG_VERSION)'"; fail=1; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "Go version pins disagree - update them together."; exit 1; \
	fi

.PHONY: build
build: | $(BUILDDIR) ; $(info Building $(BINARY_NAME)...) @ ## Build SR-IOV Network device plugin
	$Q cd $(CURDIR)/cmd/$(BINARY_NAME) && $(GO_BUILD_OPTS) go build -ldflags '$(GO_LDFLAGS)' $(GO_FLAGS) -o $(BUILDDIR)/$(BINARY_NAME) $(GO_TAGS) -v
	$(info Done!)

# Tool paths. `?=` so the build container can override them with its own
# pre-installed copies; otherwise go-get-tool installs the pinned version below
# into ./bin.
GOLANGCI_LINT ?= $(BINDIR)/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.63.4
.PHONY: golangci-lint
golangci-lint: ## Download golangci-lint locally if necessary.
	$Q $(call go-get-tool,$(GOLANGCI_LINT),github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION))

GOFILES_NO_VENDOR = $(shell find . -type f -name '*.go' -not -path "./vendor/*")
.PHONY: lint
lint: golangci-lint ; $(info  Running golangci-lint linter...) @ ## Run golangci-lint linter
	$Q if [ `gofmt -l $(GOFILES_NO_VENDOR) | wc -l` -ne 0 ]; then \
		echo There are some malformed files, please make sure to run \'make fmt\'; \
		gofmt -l $(GOFILES_NO_VENDOR); \
		exit 1; \
	fi
	$Q $(GOLANGCI_LINT) run -v --timeout 5m0s

MOCKERY ?= $(BINDIR)/mockery
$(MOCKERY): | $(BINDIR) ; $(info  installing mockery...)
	$(call go-install-tool,$(MOCKERY),github.com/vektra/mockery/v2@latest)

TEST_TARGETS := test-default test-verbose test-race
.PHONY: $(TEST_TARGETS) test
test-verbose: ARGS=-v            ## Run tests in verbose mode with coverage reporting
test-race:    ARGS=-race         ## Run tests with race detector
$(TEST_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_TARGETS): test
test: ; $(info  running $(NAME:%=% )tests...) @ ## Run tests
	$Q go test -v -timeout $(TIMEOUT)s $(ARGS) $(PKGS)

.PHONY: test-coverage
test-coverage: | $(COVERAGE_DIR) ; $(info  Running coverage tests...) @ ## Run coverage tests
	$Q go test -v -timeout 30s -cover -covermode=$(COVERAGE_MODE) -coverprofile=$(COVERAGE_PROFILE) $(PKGS)


.PHONY: deps-update
deps-update: ; $(info  Updating dependencies...) @ ## Update dependencies
	$Q go mod tidy

.PHONY: image
image: ; $(info Building Docker image...) @ ## Build SR-IOV Network device plugin docker image
# Default: builds with bundled nicctl versions (1.117.5-a-77, 1.117.5-a-147) with bootstrap 1.117.5-a-147
# Customize nicctl versions by overriding DOCKERARGS:
#   make image DOCKERARGS="--build-arg AINIC_VERSIONS=1.117.5-a-147"
#   make image DOCKERARGS="--build-arg AINIC_VERSIONS=1.117.5-a-56,1.117.5-a-77,1.117.5-a-88,1.117.5-a-103,1.117.5-a-147 --build-arg BOOTSTRAP_VERSION=1.117.5-a-147"
ifeq ($(HOURLY_TAG_LABEL),)
	$Q docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg AINIC_VERSIONS="1.117.5-a-77,1.117.5-a-147" \
		--build-arg BOOTSTRAP_VERSION="1.117.5-a-147" \
		-t $(IMG) -f $(DOCKERFILE) $(CURDIR) $(DOCKERARGS)
else
	$Q docker build \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg AINIC_VERSIONS="1.117.5-a-77,1.117.5-a-147" \
		--build-arg BOOTSTRAP_VERSION="1.117.5-a-147" \
		--label HOURLY_TAG_LABEL=$(HOURLY_TAG_LABEL) \
		-t $(IMG) -f $(DOCKERFILE) $(CURDIR) $(DOCKERARGS)
endif

.PHONY: docker-save
docker-save: | $(IMG_DIR) ; $(info Saving docker image to $(IMG_FILE_NAME).tar.gz...)
	$Q docker save $(IMG) | gzip > $(IMG_DIR)/$(IMG_FILE_NAME).tar.gz

.PHONY: clean
clean: ; $(info  Cleaning...) @ ## Cleanup everything
	@go clean --modcache --cache --testcache
	@rm -rf $(BUILDDIR)
	@rm -rf $(BINDIR)
	@rm -rf test/

.PHONY: generate-mocks
generate-mocks: | $(MOCKERY) ; $(info generating mocks...) @ ## Generate mocks
	$Q $(MOCKERY) --name=".*" --dir=pkg/types --output=pkg/types/mocks --recursive=false --log-level=debug
	$Q $(MOCKERY) --name=".*" --dir=pkg/utils --output=pkg/utils/mocks --recursive=false --log-level=debug
	$Q $(MOCKERY) --name=".*" --dir=pkg/cdi --output=pkg/cdi/mocks --recursive=false --log-level=debug

.PHONY: help
help: ; @ ## Display this help message
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: helm-update-meta
helm-update-meta:
	sed -i -e 's|appVersion:.*$$|appVersion: ${HELM_CHART_APP_VERSION}|' $(HELM_CHART_DIR)/Chart.yaml
	sed -i '0,/version:/s|version:.*|version: ${HELM_CHART_VERSION}|' $(HELM_CHART_DIR)/Chart.yaml
	sed -i -e 's|name: network-device-plugin-charts|name: ${HELM_CHART_NAME}|' $(HELM_CHART_DIR)/Chart.yaml
	sed -i -e 's|repository:.*$$|repository: ${IMAGE_TAG_BASE}|' $(HELM_CHART_DIR)/values.yaml
	sed -i -e 's|tag:.*$$|tag: ${IMAGE_TAG}|' $(HELM_CHART_DIR)/values.yaml

.PHONY: helm-lint
helm-lint:
	cd $(HELM_CHART_DIR); helm lint

HELMDOCS ?= $(BINDIR)/helm-docs
.PHONY: helm-docs
helm-docs: ## Download helm-docs locally if necessary
	$(call go-get-tool,$(HELMDOCS),github.com/norwoodj/helm-docs/cmd/helm-docs@v1.12.0)
	$(HELMDOCS) -c $(shell pwd)/helm-charts-k8s/ -g $(shell pwd)/helm-charts-k8s -u --ignore-non-descriptions

.PHONY: cleanup-stale-charts
cleanup-stale-charts:
	rm -f $(HELM_CHART_DIR)/$(HELM_CHART_NAME)-*.tgz $(HELM_CHART_DIR)/$(HELM_OUTPUT_FILE_PREFIX)-*.tgz

.PHONY: helm-package
helm-package: cleanup-stale-charts
	helm package $(HELM_CHART_DIR)/ --destination $(HELM_CHART_DIR)

.PHONY: helm
helm: helm-update-meta helm-lint helm-package helm-docs
	cp $(HELM_CHART_DIR)/$(HELM_CHART_NAME)-$(HELM_CHART_VERSION).tgz $(CHART_DEST)
	@echo "Helm chart is ready in $(CHART_DEST)"

.PHONY: helm-install
helm-install:
	helm install $(HELM_RELEASE_NAME) $(HELM_CHART_DIR)/$(HELM_CHART_NAME)-$(HELM_CHART_VERSION).tgz -f $(HELM_CHART_DIR)/values.yaml --namespace $(HELM_RELEASE_NAMESPACE) --create-namespace

.PHONY: helm-uninstall
helm-uninstall:
	helm uninstall $(HELM_RELEASE_NAME) --namespace $(HELM_RELEASE_NAMESPACE)

copyrights:
	GOFLAGS=-mod=mod go run tools/build/copyright/main.go && ${MAKE} fmt && ./tools/build/check-local-files.sh

.PHONY: docker-build-env
docker-build-env: ## Build the build container.
	@echo "Building the Docker environment..."
	$Q docker build \
		-t $(DOCKER_BUILDER_IMAGE) \
		--build-arg BUILD_BASE_IMG=$(BUILD_BASE_IMG) \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		-f Dockerfile.build .

.PHONY: docker/shell
docker/shell: docker-build-env ## Bring up and attach to a shell container that has dev environment configured
	@echo "Starting a shell in the Docker build container..."
	@mkdir -p $(BUILD_CACHE_DIR)
	@docker run --rm -it \
		-e HOME=$(CONTAINER_CACHE) \
		-e GOCACHE=$(CONTAINER_CACHE)/go \
		-e GOPATH=$(CONTAINER_CACHE)/gopath \
		-e GOFLAGS=-mod=vendor \
		-v $(CURDIR):$(CONTAINER_WORKDIR) \
		-v $(BUILD_CACHE_DIR):$(CONTAINER_CACHE) \
		--user $(shell id -u):$(shell id -g) \
		-w $(CONTAINER_WORKDIR) \
		$(DOCKER_BUILDER_IMAGE) \
		bash

# go-install-tool will 'go install' any package $2 and install it to $1.
define go-install-tool
$Q[ -f $(1) ] || { \
set -e ;\
echo "Downloading $(2)" ;\
GOBIN=$(BINDIR) go install $(2) ;\
}
endef
