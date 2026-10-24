# Personal overrides (signing identity, bundle ID) go in Makefile.local, which is git-ignored.
-include Makefile.local

# "-" signs ad hoc: fine for building and running locally. A stable certificate keeps Accessibility and
# Keychain permissions across rebuilds (see README).
IDENTITY ?= -
BUNDLE_ID ?= app.nexus.launcher
APP := build/Nexus.app

.PHONY: build run install test clean bench icon dmg universal
build:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/Nexus $(APP)/Contents/MacOS/Nexus
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" $(APP)/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" $(APP)

run: build
	-pkill -x Nexus
	open $(APP)

install: build
	-pkill -x Nexus
	rm -rf /Applications/Nexus.app
	cp -R $(APP) /Applications/Nexus.app
	open /Applications/Nexus.app

# Invisible latency benchmark: restarts Nexus in --bench mode (~40 s), prints cold/warm open times, relaunches Nexus.
bench: build
	-pkill -x Nexus
	rm -f /tmp/nexus-bench.txt
	$(APP)/Contents/MacOS/Nexus --bench
	@cat /tmp/nexus-bench.txt
	open $(APP)

# Universal (Apple Silicon + Intel) app for sharing, in build/universal/. Slower than `build`: compiles twice.
UAPP := build/universal/Nexus.app
universal:
	swift build -c release --arch arm64 --arch x86_64
	rm -rf $(UAPP)
	mkdir -p $(UAPP)/Contents/MacOS $(UAPP)/Contents/Resources
	cp .build/apple/Products/Release/Nexus $(UAPP)/Contents/MacOS/Nexus
	cp Resources/AppIcon.icns $(UAPP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(UAPP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" $(UAPP)/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" $(UAPP)
	@echo "Architectures: $$(lipo -archs $(UAPP)/Contents/MacOS/Nexus)"

# Shareable disk image (universal): Nexus.app + an Applications shortcut to drag onto.
DMG := build/Nexus.dmg
STAGE := build/dmg
dmg: universal
	rm -rf $(STAGE) $(DMG)
	mkdir -p $(STAGE)
	cp -R $(UAPP) $(STAGE)/Nexus.app
	ln -s /Applications $(STAGE)/Applications
	hdiutil create -volname Nexus -srcfolder $(STAGE) -ov -format UDZO $(DMG)
	rm -rf $(STAGE)
	@echo "Created $(DMG)"

test:
	swift test

# Regenerate the app icon (the ⌘ glyph on a dark squircle).
icon:
	swift tools/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build build
