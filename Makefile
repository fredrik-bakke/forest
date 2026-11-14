SHELL := /bin/bash

FORESTER ?= ./_opam/bin/forester
XSLTPROC ?= xsltproc
FOREST_CONFIG ?= forest.toml
WATCH_PATHS ?= trees theme assets Makefile $(FOREST_CONFIG)

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

# Transform only Forester's plain bibliography blocks, preserving the surrounding HTML.
build-forest:
	@"$(FORESTER)" build "$(FOREST_CONFIG)"
	@set -e; export XSLTPROC="$(XSLTPROC)"; \
	while IFS= read -r -d '' page; do \
		if ! perl -MIPC::Open2 -0777 -pe ' \
			s{<pre>\s*\@[^<]*</pre>}{ \
				my $$block = $$&; \
				my $$pid = open2(my $$out, my $$in, $$ENV{XSLTPROC}, "--nonet", "--novalid", "theme/static.xsl", "-"); \
				print {$$in} $$block; close $$in or die "Cannot send bibliography to XSLT: $$!"; \
				my $$result = do { local $$/; <$$out> }; close $$out; \
				waitpid($$pid, 0); die "Bibliography XSLT failed\n" if $$?; \
				$$result =~ s/\n\z//; $$result; \
			}gse; \
		' "$$page" > "$$page.tmp"; then \
			rm -f "$$page.tmp"; \
			exit 1; \
		fi; \
		mv "$$page.tmp" "$$page"; \
	done < <(find output -type f -name '*.html' -print0)

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
