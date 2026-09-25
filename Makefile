SHELL := /bin/bash
.DEFAULT_GOAL := build

RUSTUP ?= rustup
RUSTUP_CARGO := $(shell $(RUSTUP) which cargo 2>/dev/null)
RUSTUP_BIN_DIR := $(dir $(RUSTUP_CARGO))
CARGO ?= $(if $(strip $(RUSTUP_CARGO)),env PATH="$(RUSTUP_BIN_DIR):$$PATH" "$(RUSTUP_CARGO)",cargo)
CARGO_TARGET_DIR ?= target
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DESKTOP_INSTALL_DIR ?= $(HOME)/Applications

TUI_BINARY = $(CARGO_TARGET_DIR)/release/xai-grok-pager
DESKTOP_APP = desktop/macOS/dist/Grok Desktop.app
TEST_BUILD_DIR = $(CURDIR)/target/test-builds
TEST_TUI_DIR = $(TEST_BUILD_DIR)/tui
TEST_TUI_BINARY = $(TEST_TUI_DIR)/grok-test
TEST_DESKTOP_DIR = $(TEST_BUILD_DIR)/desktop
TEST_DESKTOP_APP = $(TEST_DESKTOP_DIR)/Grok Desktop Test.app
TEST_DESKTOP_STATE = $(TEST_BUILD_DIR)/desktop-state/state.json
TEST_DESKTOP_ICON = $(TEST_DESKTOP_DIR)/GrokDesktopTestIcon.icns

.PHONY: build deploy build-desktop deploy-desktop dmg-desktop build-test-tui build-test-desktop help

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

# Test artifacts stay under this checkout. bin/grok-test refuses to launch from another workspace.
build-test-tui:
	$(CARGO) build -p xai-grok-pager-bin --release --target-dir "$(CARGO_TARGET_DIR)"
	@mkdir -p "$(TEST_TUI_DIR)"
	@set -e; \
		tmp_binary=$$(mktemp "$(TEST_TUI_BINARY).XXXXXX"); \
		trap 'rm -f "$$tmp_binary"' EXIT; \
		install -m 755 "$(TUI_BINARY)" "$$tmp_binary"; \
		mv -f "$$tmp_binary" "$(TEST_TUI_BINARY)"
	@printf 'Built test TUI: %s\n' "$(TEST_TUI_BINARY)"
	@printf 'Launch it with: PATH="%s/bin:$$PATH" grok-test\n' "$(CURDIR)"

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

# This bundle has a separate identity, test-only artwork, and workspace-local UI state.
build-test-desktop: build-test-tui
	@if [ "$$(uname -s)" != Darwin ]; then \
		printf 'The test desktop app requires macOS.\n' >&2; exit 1; \
	fi
	@mkdir -p "$(TEST_DESKTOP_DIR)"
	DESKTOP_APP_NAME="Grok Desktop Test" \
	DESKTOP_BUNDLE_ID="ai.grok.build.desktop.test" \
	DESKTOP_APP_DIR="$(TEST_DESKTOP_APP)" \
	DESKTOP_ICON_PATH="$(TEST_DESKTOP_ICON)" \
	DESKTOP_ICON_PREVIEW_PATH="$(dir $(TEST_DESKTOP_ICON))Grok Desktop Test-icon.png" \
	DESKTOP_ICON_STYLE="test" \
	DESKTOP_STATE_FILE="$(TEST_DESKTOP_STATE)" \
	DESKTOP_TEST_BUILD=1 \
	DESKTOP_REGISTER_APP=0 \
	GROK_BINARY="$(TEST_TUI_BINARY)" ./desktop/macOS/scripts/build-app.sh
	@printf 'Launch with: open "%s"\n' "$(TEST_DESKTOP_APP)"

help:
	@printf '%s\n' \
		'make / make build       Build the release CLI/TUI only (default).' \
		'make deploy             Build and install the TUI to ~/.local/bin/grok.' \
		'make build-desktop      Build the harness and package the macOS desktop app.' \
		'make deploy-desktop     Build and install the desktop app to ~/Applications.' \
		'make dmg-desktop        Build the desktop app and its .dmg installer in desktop/macOS/dist.' \
		'make build-test-tui     Build the workspace-only TUI used by grok-test.' \
		'make build-test-desktop Build the orange, TESTING-badged desktop app in target/test-builds.' \
		'' \
		'Overrides: CARGO, RUSTUP, CARGO_TARGET_DIR, PREFIX, BINDIR, DESKTOP_INSTALL_DIR.' \
		'Set GROK_BINARY to reuse an existing harness when building the desktop app.'
