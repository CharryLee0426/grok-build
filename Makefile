SHELL := /bin/bash
.DEFAULT_GOAL := build

CARGO ?= cargo
CARGO_TARGET_DIR ?= target
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DESKTOP_INSTALL_DIR ?= $(HOME)/Applications

TUI_BINARY = $(CARGO_TARGET_DIR)/release/xai-grok-pager
DESKTOP_APP = desktop/macOS/dist/Grok Desktop.app

.PHONY: build deploy build-desktop deploy-desktop dmg-desktop help

# The default build and deploy commands only operate on the CLI/TUI.
build:
	$(CARGO) build -p xai-grok-pager-bin --release --target-dir "$(CARGO_TARGET_DIR)"

deploy: build
	@mkdir -p "$(BINDIR)"
	@set -e; \
		tmp_binary=$$(mktemp "$(BINDIR)/.grok.XXXXXX"); \
		trap 'rm -f "$$tmp_binary"' EXIT; \
		install -m 755 "$(TUI_BINARY)" "$$tmp_binary"; \
		mv -f "$$tmp_binary" "$(BINDIR)/grok"
	@printf 'Installed TUI: %s/grok\n' "$(BINDIR)"

# Desktop packaging needs a harness. An explicit GROK_BINARY reuses that
# executable; otherwise build the current checkout before bundling it.
build-desktop:
	@if [ "$$(uname -s)" != Darwin ]; then \
		printf 'Grok Desktop requires macOS.\n' >&2; exit 1; \
	fi
ifeq ($(strip $(GROK_BINARY)),)
	$(MAKE) build
endif
	GROK_BINARY="$(if $(strip $(GROK_BINARY)),$(GROK_BINARY),$(TUI_BINARY))" ./desktop/macOS/scripts/build-app.sh

deploy-desktop: build-desktop
	@mkdir -p "$(DESKTOP_INSTALL_DIR)/Grok Desktop.app"
	rsync -a --delete "$(DESKTOP_APP)/" "$(DESKTOP_INSTALL_DIR)/Grok Desktop.app/"
	@printf 'Installed desktop app: %s/Grok Desktop.app\n' "$(DESKTOP_INSTALL_DIR)"

# The installer for new users: the app, with its bundled TUI, on a drag-to-Applications disk image.
dmg-desktop: build-desktop
	./desktop/macOS/scripts/build-dmg.sh

help:
	@printf '%s\n' \
		'make / make build     Build the release CLI/TUI only (default).' \
		'make deploy           Build and install the TUI to ~/.local/bin/grok.' \
		'make build-desktop    Build the harness and package the macOS desktop app.' \
		'make deploy-desktop   Build and install the desktop app to ~/Applications.' \
		'make dmg-desktop      Build the desktop app and its .dmg installer in desktop/macOS/dist.' \
		'' \
		'Overrides: CARGO, CARGO_TARGET_DIR, PREFIX, BINDIR, DESKTOP_INSTALL_DIR.' \
		'Set GROK_BINARY to reuse an existing harness when building the desktop app.'
