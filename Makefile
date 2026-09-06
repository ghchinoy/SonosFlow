.PHONY: all build run run-cli spike test app docs-install docs-dev docs-build docs-preview clean help

all: build

help:
	@echo "SonosFlow - Standalone macOS Sonos Controller"
	@echo "Available make targets:"
	@echo "  make run          - Fast build & launch SonosFlow.app"
	@echo "  make run-cli      - Launch directly in Terminal via swift run"
	@echo "  make build        - Compile debug binaries"
	@echo "  make spike        - Run the Sonos MCP verification spike"
	@echo "  make test         - Run automated unit test suite"
	@echo "  make app          - Build optimized release SonosFlow.app bundle"
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

test:
	@echo "🧪 Running unit tests..."
	@mkdir -p .cache/clang .cache/tmp
	@swift test $(SWIFT_FLAGS)

app:
	@./scripts/build_app.sh --release

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
