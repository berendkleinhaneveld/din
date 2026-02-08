APP_NAME = Box
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS

.PHONY: build run app clean

build:
	swift build

run: build
	.build/debug/Box

app: build
	mkdir -p $(MACOS)
	cp .build/debug/Box $(MACOS)/Box
	cp Box/Info.plist $(CONTENTS)/Info.plist
	@echo "Built $(APP_BUNDLE)"
	@echo "Run with: open $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
