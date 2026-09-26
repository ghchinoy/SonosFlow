.PHONY: all build run run-cli spike official-spike test app install uninstall docs-install docs-dev docs-build docs-preview clean help

all: build

INSTALL_DIR ?= $(HOME)/Applications
LSREGISTER ?= /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

help:
	@echo "SonosFlow - Standalone macOS Sonos Controller"
	@echo "Available make targets:"
	@echo "  make run            - Fast build & launch SonosFlow.app"
	@echo "  make run-cli        - Launch directly in Terminal via swift run"
	@echo "  make build          - Compile debug binaries"
	@echo "  make spike          - Run local homectl Sonos MCP spike"
	@echo "  make official-spike - Run official hosted Sonos 27mcp spike"
	@echo "  make test           - Run automated unit test suite"
	@echo "  make app          - Build optimized release SonosFlow.app bundle"
	@echo "  make install      - Install release bundle to ~/Applications (or INSTALL_DIR=...)"
	@echo "  make uninstall    - Remove bundle from ~/Applications"
	@echo "  make docs-install - Install Astro Starlight docs dependencies"
	@echo "  make docs-dev     - Run local Starlight documentation server"
	@echo "  make docs-build   - Build static production documentation site"
	@echo "  make docs-preview - Preview the built static documentation"
	@echo "  make clean        - Remove build artifacts and temporary files"

SWIFT_FLAGS ?= --disable-sandbox -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc $$(PWD)/.cache/clang -Xswiftc -module-cache-path -Xswiftc $$(PWD)/.cache/clang

build:
	@echo "🔨 Building SonosFlow..."
	@mkdir -p .cache/clang .cache/tmp
	@swift build $(SWIFT_FLAGS)

run:
	@./scripts/build_app.sh
	@echo "🚀 Opening SonosFlow.app..."
	@open SonosFlow.app

run-cli:
	@echo "🚀 Launching SonosFlow in terminal..."
	@mkdir -p .cache/clang .cache/tmp
	@swift run $(SWIFT_FLAGS) SonosFlow

spike:
	@echo "🎵 Running Sonos MCP Spike..."
	@mkdir -p .cache/clang .cache/tmp
	@swift run $(SWIFT_FLAGS) SonosFlowSpike

official-spike:
	@echo "🌐 Running Official Sonos 27mcp Spike..."
	@mkdir -p .cache/clang .cache/tmp
	@swift run $(SWIFT_FLAGS) SonosOfficialMCPSpike

test:
	@echo "🧪 Running unit tests..."
	@mkdir -p .cache/clang .cache/tmp
	@swift test $(SWIFT_FLAGS)

app:
	@./scripts/build_app.sh --release

install: app
	@echo "📦 Installing SonosFlow.app to $(INSTALL_DIR)..."
	@osascript -e 'quit app "SonosFlow"' 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/SonosFlow.app"
	@ditto SonosFlow.app "$(INSTALL_DIR)/SonosFlow.app"
	@codesign --force --deep --sign - "$(INSTALL_DIR)/SonosFlow.app" 2>/dev/null || true
	@if [ -x "$(LSREGISTER)" ]; then \
		"$(LSREGISTER)" -f "$(INSTALL_DIR)/SonosFlow.app"; \
	fi
	@echo "✅ Successfully installed to $(INSTALL_DIR)/SonosFlow.app"
	@echo "   Run: open $(INSTALL_DIR)/SonosFlow.app"

uninstall:
	@echo "🗑️  Uninstalling SonosFlow.app from $(INSTALL_DIR)..."
	@osascript -e 'quit app "SonosFlow"' 2>/dev/null || true
	@if [ -x "$(LSREGISTER)" ] && [ -d "$(INSTALL_DIR)/SonosFlow.app" ]; then \
		"$(LSREGISTER)" -u "$(INSTALL_DIR)/SonosFlow.app" 2>/dev/null || true; \
	fi
	@rm -rf "$(INSTALL_DIR)/SonosFlow.app"
	@echo "✅ Removed $(INSTALL_DIR)/SonosFlow.app"
	@echo "ℹ️  User settings, Keychain tokens, and artwork cache were preserved."
	@echo "   To remove settings: defaults delete com.sonosflow.app"
	@echo "   To remove artwork cache: rm -rf ~/Library/Caches/com.sonosflow.app"

docs-install:
	@echo "📦 Installing Starlight documentation dependencies..."
	@pnpm --prefix docs install

docs-dev:
	@echo "📚 Starting Starlight development server..."
	@pnpm --prefix docs dev

docs-build:
	@echo "🏗️ Building Starlight documentation site..."
	@pnpm --prefix docs build

docs-preview:
	@echo "👀 Previewing Starlight documentation..."
	@pnpm --prefix docs preview

clean:
	@echo "🧹 Cleaning workspace..."
	@swift package clean
	@rm -rf .build SonosFlow.app .cache docs/dist docs/.astro
	@echo "✅ Clean complete."
