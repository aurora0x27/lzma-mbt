# lzma-mbt developer shortcuts.
# Gates align with CI / task.md / docs/research/toolchain.md.
#
# Compatible with macOS /usr/bin/make (GNU Make 3.81).

MOON   ?= moon
PYTHON ?= python3

.PHONY: help check fmt fmt-check test diff examples examples-fixtures clean ci all \
	example-p1 example-p2 example-p3 example-p4 example-p5

.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make check              - moon check --deny-warn"
	@echo "  make fmt                - moon fmt (rewrite)"
	@echo "  make fmt-check          - moon fmt --check"
	@echo "  make test               - moon test --deny-warn"
	@echo "  make diff               - python3 scripts/diff_encode.py"
	@echo "  make examples-fixtures  - ensure fixtures/large.png exists"
	@echo "  make examples           - run examples/p1..p5 (typical inputs)"
	@echo "  make example-pN         - moon run examples/pN  (N=1..5)"
	@echo "  make ci / all           - check + fmt-check + test + diff"
	@echo "  make clean              - remove _build/ and example out/"

check:
	$(MOON) check --deny-warn

fmt:
	$(MOON) fmt

fmt-check:
	$(MOON) fmt --check

test:
	$(MOON) test --deny-warn

diff:
	$(PYTHON) scripts/diff_encode.py

# Large image is not committed; copy a local wallpaper if missing.
examples-fixtures:
	@mkdir -p examples/fixtures examples/p1/out examples/p2/out examples/p3/out examples/p4/out examples/p5/out
	@if [ ! -f examples/fixtures/large.png ]; then \
	  if [ -f "$(HOME)/Pictures/wallpaper/CuteCat.png" ]; then \
	    cp "$(HOME)/Pictures/wallpaper/CuteCat.png" examples/fixtures/large.png; \
	    echo "prepared examples/fixtures/large.png from Pictures/wallpaper/CuteCat.png"; \
	  elif [ -f "$(HOME)/Pictures/wallpaper/River.png" ]; then \
	    cp "$(HOME)/Pictures/wallpaper/River.png" examples/fixtures/large.png; \
	    echo "prepared examples/fixtures/large.png from Pictures/wallpaper/River.png"; \
	  else \
	    echo "error: examples/fixtures/large.png missing;"; \
	    echo "  copy any large PNG/JPEG to examples/fixtures/large.png"; \
	    exit 1; \
	  fi; \
	fi
	@test -f examples/fixtures/small.txt
	@test -f examples/fixtures/large.txt
	@test -f examples/fixtures/syslog.log
	@test -f examples/fixtures/small.png

examples: examples-fixtures example-p1 example-p2 example-p3 example-p4 example-p5

example-p1: examples-fixtures
	@mkdir -p examples/p1/out
	$(MOON) run examples/p1

example-p2: examples-fixtures
	@mkdir -p examples/p2/out
	$(MOON) run examples/p2

example-p3: examples-fixtures
	@mkdir -p examples/p3/out
	$(MOON) run examples/p3

example-p4: examples-fixtures
	@mkdir -p examples/p4/out
	$(MOON) run examples/p4

example-p5: examples-fixtures
	@mkdir -p examples/p5/out
	$(MOON) run examples/p5

ci all: check fmt-check test diff

clean:
	rm -rf _build
	rm -rf examples/p1/out examples/p2/out examples/p3/out examples/p4/out examples/p5/out
