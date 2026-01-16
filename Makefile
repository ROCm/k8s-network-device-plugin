#
# Credit:
#   This makefile was adapted from: https://github.com/vincentbernat/hellogopher/blob/feature/glide/Makefile
#
# Go environment

# Import development related environment variables from dev.env
ifneq ("$(wildcard dev.env)","")
    include dev.env
endif

PROJECT_VERSION ?= v0.0.1

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

.PHONY: all
all: lint build test

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: create-dirs
create-dirs: $(DIRS)

$(DIRS): ; $(info Creating directory $@...)
	$Q mkdir -p $@

.PHONY: build
build: | $(BUILDDIR) ; $(info Building $(BINARY_NAME)...) @ ## Build SR-IOV Network device plugin
	$Q cd $(CURDIR)/cmd/$(BINARY_NAME) && $(GO_BUILD_OPTS) go build -ldflags '$(GO_LDFLAGS)' $(GO_FLAGS) -o $(BUILDDIR)/$(BINARY_NAME) $(GO_TAGS) -v
	$(info Done!)

GOLANGCI_LINT = $(BINDIR)/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.63.4
$(GOLANGCI_LINT): | $(BINDIR) ; $(info  installing golangci-lint...)
	$Q[ -f $(GOLANGCI_LINT) ] || { \
	set -e ;\
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell dirname $(GOLANGCI_LINT)) $(GOLANGCI_LINT_VERSION) ;\
	}

MOCKERY = $(BINDIR)/mockery
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

.PHONY: lint
lint: $(GOLANGCI_LINT) ; $(info  Running golangci-lint linter...) @ ## Run golangci-lint linter
	$Q $(GOLANGCI_LINT) run

.PHONY: deps-update
deps-update: ; $(info  Updating dependencies...) @ ## Update dependencies
	$Q go mod tidy

.PHONY: image
image: ; $(info Building Docker image...) @ ## Build SR-IOV Network device plugin docker image
ifeq ($(HOURLY_TAG_LABEL),)
	$Q docker build -t $(IMG) -f $(DOCKERFILE)  $(CURDIR) $(DOCKERARGS)
else
	$Q docker build --label HOURLY_TAG_LABEL=$(HOURLY_TAG_LABEL) -t $(IMG) -f $(DOCKERFILE)  $(CURDIR) $(DOCKERARGS)
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

HELMDOCS = $(shell pwd)/bin/helm-docs
.PHONY: helm-docs
helm-docs: ## Download helm-docs locally if necessary
	$(call go-get-tool,$(HELMDOCS),github.com/norwoodj/helm-docs/cmd/helm-docs@v1.12.0)
	$(HELMDOCS) -c $(shell pwd)/helm-charts-k8s/ -g $(shell pwd)/helm-charts-k8s -u --ignore-non-descriptions


.PHONY: helm-package
helm-package:
	helm package $(HELM_CHART_DIR)/ --destination $(HELM_CHART_DIR)

.PHONY: helm
helm: helm-update-meta helm-lint helm-package helm-docs
	$(eval HELM_OUTPUT_FILE_NAME ?= k8s-network-device-plugin-helm-k8s-$(PROJECT_VERSION).tgz)
	$(eval CHART_DEST := $(HELM_CHART_DIR)/$(HELM_OUTPUT_FILE_NAME))
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

# go-install-tool will 'go install' any package $2 and install it to $1.
define go-install-tool
$Q[ -f $(1) ] || { \
set -e ;\
echo "Downloading $(2)" ;\
GOBIN=$(BINDIR) go install $(2) ;\
}
endef
