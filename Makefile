APP_NAME = Din
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS

.PHONY: build run app clean lint format

build:
	swift build

run: build
	.build/debug/Din

app: build
	mkdir -p $(MACOS) $(CONTENTS)/Resources
	cp .build/debug/Din $(MACOS)/Din
	cp Din/Info.plist $(CONTENTS)/Info.plist
	cp Din/Assets/Din.icns $(CONTENTS)/Resources/Din.icns
	@echo "Built $(APP_BUNDLE)"
	@echo "Run with: open $(APP_BUNDLE)"

lint:
	swift format lint --strict --recursive --parallel Din/

format:
	swift format lint --strict --recursive --parallel Din/

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
