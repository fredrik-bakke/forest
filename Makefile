SHELL := /bin/bash

FORESTER ?= ./_opam/bin/forester
XSLTPROC ?= xsltproc
FOREST_CONFIG ?= forest.toml
WATCH_PATHS ?= trees theme assets scripts Makefile $(FOREST_CONFIG)
BUILD_LOCK := $(if $(shell command -v flock),flock,lockf -k) .forest-build.lock

.PHONY: help build build-forest publish-forest watch watch-forest watch-forest-changes clean clean-forester

help:
	@echo "Available targets:"
	@echo "  make build (or make build-forest)"
	@echo "    # Build the forest"
	@echo "  make watch (or make watch-forest)"
	@echo "    # Build and rebuild when sources or build configuration change"
	@echo "  make clean (or make clean-forester)"
	@echo "    # Remove generated build and output directories"

build: build-forest

# Serialize publication when a manual build overlaps the watcher.
build-forest:
	@$(BUILD_LOCK) $(MAKE) --no-print-directory publish-forest

publish-forest:
	@set -eu; stage=$$(mktemp -d); trap 'rm -rf "$$stage"' EXIT; \
	ln -s "$(abspath trees)" "$(abspath assets)" "$(abspath theme)" "$$stage/"; \
	ln -s "$(abspath $(FOREST_CONFIG))" "$$stage/forest.toml"; \
	mkdir -p build/resources "$$stage/build/resources"; \
	rsync -rc build/resources/ "$$stage/build/resources/"; \
	"$(FORESTER)" build --emit-xml --no-theme "$$stage/forest.toml"; \
	"$(FORESTER)" build "$$stage/forest.toml"; \
	python3 scripts/postprocess.py --xsltproc "$(XSLTPROC)" "$$stage/output"; \
	rsync -r --exclude='.*' assets/ "$$stage/output/forest/assets/"; \
	rsync -rc "$$stage/build/resources/" build/resources/; \
	rsync -rc --delay-updates --delete-after "$$stage/output/" output/

watch: watch-forest

watch-forest: build-forest
	@$(MAKE) --no-print-directory watch-forest-changes

watch-forest-changes:
	@set -o pipefail; \
	fswatch -o $(WATCH_PATHS) | while read -r _; do \
		echo "Rebuilding forest"; \
		if time $(MAKE) --no-print-directory build-forest; then \
			echo "Done"; \
		fi; \
		echo; \
	done

clean: clean-forester

clean-forester:
	@$(BUILD_LOCK) rm -rf build output
