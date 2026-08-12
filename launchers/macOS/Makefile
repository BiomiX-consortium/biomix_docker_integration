# Builds "BiomiX Launcher.app" (via build.sh) and packages it into a
# distributable, ad-hoc-signed .dmg.

APP_NAME    := BiomiX Launcher
VERSION     := $(shell sed -n 's/^VERSION="\(.*\)"/\1/p' build.sh)

ROOT        := $(CURDIR)
BUILD       := $(ROOT)/build
APP         := $(BUILD)/$(APP_NAME).app
DMG_STAGING := $(BUILD)/dmg-staging
DMG_NAME    := BiomiX-Launcher-$(VERSION).dmg
DMG         := $(BUILD)/$(DMG_NAME)

.PHONY: all app dmg open clean

all: dmg

# build.sh always does a clean rebuild, so just delegate to it every time.
app:
	./build.sh

dmg: app
	@echo "==> Creating $(DMG_NAME)"
	rm -rf "$(DMG_STAGING)"
	mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP)" "$(DMG_STAGING)/"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	rm -f "$(DMG)"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO "$(DMG)"
	rm -rf "$(DMG_STAGING)"
	@echo "Built: $(DMG)"

open: app
	open "$(APP)"

clean:
	rm -rf "$(BUILD)"
