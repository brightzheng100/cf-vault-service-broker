# Metadata about this makefile and position
MKFILE_PATH := $(lastword $(MAKEFILE_LIST))
CURRENT_DIR := $(dir $(realpath $(MKFILE_PATH)))
CURRENT_DIR := $(CURRENT_DIR:/=)

# Get the project metadata
GOVERSION := 1.7.4
VERSION := 0.1.0
PROJECT := github.com/hashicorp/cf-vault-broker
OWNER := $(dir $(PROJECT))
OWNER := $(notdir $(OWNER:/=))
NAME := $(notdir $(PROJECT))
EXTERNAL_TOOLS =

# Current system information (this is the invoking system)
ME_OS = $(shell go env GOOS)
ME_ARCH = $(shell go env GOARCH)

# Default os-arch combination to build
XC_OS ?= linux
XC_ARCH ?= amd64
XC_EXCLUDE ?=

# GPG Signing key (blank by default, means no GPG signing)
GPG_KEY ?=

# List of tests to run
TEST ?= ./...

# List all our actual files, excluding vendor
GOFILES = $(shell go list $(TEST) | grep -v /vendor/)

# bin builds the project by invoking the compile script inside of a Docker
# container. Invokers can override the target OS or architecture using
# environment variables.
bin:
	@echo "==> Building ${PROJECT}..."
	@docker run \
		--rm \
		--env="VERSION=${VERSION}" \
		--env="PROJECT=${PROJECT}" \
		--env="OWNER=${OWNER}" \
		--env="NAME=${NAME}" \
		--env="XC_OS=${XC_OS}" \
		--env="XC_ARCH=${XC_ARCH}" \
		--env="XC_EXCLUDE=${XC_EXCLUDE}" \
		--env="DIST=${DIST}" \
		--workdir="/go/src/${PROJECT}" \
		--volume="${CURRENT_DIR}:/go/src/${PROJECT}" \
		"golang:${GOVERSION}" /usr/bin/env sh -c "scripts/compile.sh"

# bin-local builds the project using the local go environment. This is only
# recommended for advanced users or users who do not wish to use the Docker
# build process.
bin-local:
	@echo "==> Building ${PROJECT} (locally)..."
	@env \
		VERSION="${VERSION}" \
		PROJECT="${PROJECT}" \
		OWNER="${OWNER}" \
		NAME="${NAME}" \
		XC_OS="${XC_OS}" \
		XC_ARCH="${XC_ARCH}" \
		XC_EXCLUDE="${XC_EXCLUDE}" \
		DIST="${DIST}" \
		/usr/bin/env sh -c "scripts/compile.sh"

# bootstrap installs the necessary go tools for development or build
bootstrap:
	@echo "==> Bootstrapping ${PROJECT}..."
	@for t in ${EXTERNAL_TOOLS}; do \
		echo "--> Installing "$$t"..." ; \
		go get -u "$$t"; \
	done

# deps gets all the dependencies for this repository and vendors them.
deps:
	@echo "==> Updating dependencies..."
	@docker run \
		--rm \
		--workdir="/go/src/${PROJECT}" \
		--volume="${CURRENT_DIR}:/go/src/${PROJECT}" \
		"golang:${GOVERSION}" /usr/bin/env sh -c "go get -u github.com/kardianos/govendor && rm -rf vendor/ && govendor init && govendor fetch -v +outside"

# dev builds the project for the current system as defined by go env.
dev:
	@env \
		XC_OS="${ME_OS}" \
		XC_ARCH="${ME_ARCH}" \
		$(MAKE) -f "${MKFILE_PATH}" bin
	@echo "--> Moving into bin/"
	@mkdir -p "${CURRENT_DIR}/bin/"
	@cp "${CURRENT_DIR}/pkg/${ME_OS}_${ME_ARCH}/${NAME}" "${CURRENT_DIR}/bin/"
ifdef GOPATH
	@echo "--> Moving into GOPATH/"
	@mkdir -p "${GOPATH}/bin/"
	@cp "${CURRENT_DIR}/pkg/${ME_OS}_${ME_ARCH}/${NAME}" "${GOPATH}/bin/"
endif

# dist builds the binaries and then signs and packages them for distribution
dist:
	@${MAKE} -f "${MKFILE_PATH}" bin DIST=1
	@echo "==> Tagging release (v${VERSION})..."
ifdef GPG_KEY
	@git commit --allow-empty --gpg-sign="${GPG_KEY}" -m "Release v${VERSION}"
	@git tag -a -m "Version ${VERSION}" -s -u "${GPG_KEY}" "v${VERSION}" master
	@gpg --default-key "${GPG_KEY}" --detach-sig "${CURRENT_DIR}/pkg/dist/${NAME}_${VERSION}_SHA256SUMS"
else
	@git commit --allow-empty -m "Release v${VERSION}"
	@git tag -a -m "Version ${VERSION}" "v${VERSION}" master
endif

# test runs the test suite
test:
	@echo "==> Testing ${PROJECT}..."
	@go test -timeout=60s -parallel=10 ${GOFILES} ${TESTARGS}

# test-race runs the race checker
test-race:
	@echo "==> Testing ${PROJECT} (race)..."
	@go test -timeout=60s -race ${GOFILES} ${TESTARGS}

.PHONY: bin bin-local bootstrap deps dev dist test test-race
