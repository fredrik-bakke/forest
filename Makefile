SHELL := /bin/bash

FORESTER ?= ./_opam/bin/forester
XSLTPROC ?= xsltproc
FOREST_CONFIG ?= forest.toml
WATCH_PATHS ?= trees theme assets scripts Makefile $(FOREST_CONFIG)

.PHONY: help build build-forest watch watch-forest clean clean-forester

help:
	@echo "Available targets:"
	@echo "  make build (or make build-forest)"
	@echo "    # Build the forest"
	@echo "  make watch (or make watch-forest)"
	@echo "    # Build and rebuild when sources or build configuration change"
	@echo "  make clean (or make clean-forester)"
	@echo "    # Remove generated build and output directories"

build: build-forest

# Apply static theme enhancements, preserving the surrounding HTML.
build-forest:
	@"$(FORESTER)" build --emit-xml --no-theme "$(FOREST_CONFIG)"
	@"$(FORESTER)" build "$(FOREST_CONFIG)"
	@python3 scripts/postprocess.py --xsltproc "$(XSLTPROC)" output
	@set -e; \
	while IFS= read -r -d '' asset; do \
		mkdir -p "output/forest/$$(dirname "$$asset")"; \
		cp "$$asset" "output/forest/$$asset"; \
	done < <(find assets -type f ! -path '*/.*' -print0)

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
