SHELL := /bin/bash

FORESTER ?= ./_opam/bin/forester
XSLTPROC ?= xsltproc
FOREST_CONFIG ?= forest.toml
WATCH_PATHS ?= trees theme assets Makefile $(FOREST_CONFIG)

INLINE_STYLES_FILTER = \
	BEGIN { \
		sub read_css { \
			my ($$path) = @_; \
			open my $$file, "<", $$path or die "Cannot read $$path: $$!"; \
			local $$/; return <$$file>; \
		} \
		our $$site_css = read_css("theme/style.css"); \
		my $$custom_css = read_css("theme/custom.css"); \
		$$site_css =~ s{\@import url\("custom\.css"\);}{$$custom_css}; \
	} \
	s{<link\s+rel="stylesheet"\s+href="([^"]*/|)style\.css"\s*/?>}{ \
		my $$base = $$1; \
		my $$css = $$site_css; \
		$$css =~ s{url\((["\x27]?)(fonts/[^)"\x27]+|(?:github|mastodon|orcid)\.svg)\1\)}{url($$1$$base$$2$$1)}g; \
		"<style>\n$$css</style>"; \
	}ge;

BIBLIOGRAPHY_FILTER = \
	s{<pre>\s*\@[^<]*</pre>}{ \
		my $$block = $$&; \
		my $$pid = open2(my $$out, my $$in, $$ENV{XSLTPROC}, "--nonet", "--novalid", "theme/static.xsl", "-"); \
		print {$$in} $$block; close $$in or die "Cannot send bibliography to XSLT: $$!"; \
		my $$result = do { local $$/; <$$out> }; close $$out; \
		waitpid($$pid, 0); die "Bibliography XSLT failed\n" if $$?; \
		$$result =~ s/\n\z//; $$result; \
	}gse;

SEARCH_BUTTON_FILTER = \
	s{(<div\s+class="logo">.*?)(</div>)}{$$1<button id="search-button" type="button" title="Search" aria-label="Search" aria-haspopup="dialog" onclick="document.dispatchEvent(new KeyboardEvent(&quot;keydown&quot;, {key: &quot;k&quot;, ctrlKey: true, bubbles: true}))"><svg width="24" height="18" viewBox="0 0 24 24" aria-hidden="true"><use href="/forest/search.svg\#icon"></use></svg></button>$$2}gs;

PREFORMATTED_FILTER = \
	s{(<pre\b[^>]*>)\n}{$$1<!--This is a guard for intentional leading blank lines.-->}g;

METADATA_FILTER = \
	my $$xml = $$ARGV; $$xml =~ s{\.html\z}{.xml}; \
	if (-f $$xml) { \
		my $$xml_uri = Cwd::abs_path($$xml); \
		$$xml_uri =~ s{([^A-Za-z0-9/._~-])}{sprintf "%%%02X", ord $$1}ge; \
		my @headers = m{(<header>.*?</header>)}sg; \
		my $$pid = open2(my $$out, my $$in, $$ENV{XSLTPROC}, "--nonet", "--novalid", \
			"--stringparam", "tree-xml", "file://$$xml_uri", "theme/local-metadata.xsl", "-"); \
		print {$$in} "<headers>", @headers, "</headers>"; close $$in or die "Cannot send headers to XSLT: $$!"; \
		my $$result = do { local $$/; <$$out> }; close $$out; \
		waitpid($$pid, 0); die "Metadata XSLT failed for $$ARGV\n" if $$?; \
		my @updated = $$result =~ m{(<header>.*?</header>)}sg; \
		die "Metadata header count changed for $$ARGV\n" unless @headers == @updated; \
		s{<header>.*?</header>}{shift @updated}gse; \
	}

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
	@set -e; export XSLTPROC="$(XSLTPROC)"; \
	while IFS= read -r -d '' page; do \
		if ! perl -MCwd -MIPC::Open2 -0777 -pe '$(INLINE_STYLES_FILTER) $(METADATA_FILTER) $(BIBLIOGRAPHY_FILTER) $(PREFORMATTED_FILTER) $(SEARCH_BUTTON_FILTER)' "$$page" > "$$page.tmp"; then \
			rm -f "$$page.tmp"; \
			exit 1; \
		fi; \
		mv "$$page.tmp" "$$page"; \
	done < <(find output -type f -name '*.html' -print0)
	@set -e; \
	while IFS= read -r -d '' asset; do \
		mkdir -p "output/forest/$$(dirname "$$asset")"; \
		cp "$$asset" "output/forest/$$asset"; \
	done < <(find assets -type f -name '*.pdf' -print0)

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
