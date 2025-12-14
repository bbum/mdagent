# Configuration
PREFIX ?= ~/.local
BINDIR ?= $(PREFIX)/bin
CONFIG ?= release

# Targets
.PHONY: build install clean

build:
	swift build -c $(CONFIG)

install: build
	@mkdir -p $(BINDIR)
	@rm -f $(BINDIR)/spot
	cp .build/$(CONFIG)/spot $(BINDIR)/

clean:
	swift package clean
