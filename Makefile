SHELL := /bin/bash

FORESTER ?= ./_opam/bin/forester
FOREST_CONFIG ?= forest.toml
WATCH_PATHS ?= trees theme assets $(FOREST_CONFIG)

.PHONY: help build build-forest watch watch-forest clean clean-forester

help:
	@echo "Available targets:"
	@echo "  make build (or make build-forest)"
	@echo "    # Build the forest"
	@echo "  make watch (or make watch-forest)"
	@echo "    # Build and rebuild when trees, theme, assets, or config change"
	@echo "  make clean (or make clean-forester)"
	@echo "    # Remove generated build and output directories"

build: build-forest

build-forest:
	@"$(FORESTER)" build "$(FOREST_CONFIG)"

watch: watch-forest

watch-forest: build-forest
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
	@rm -rf build output
