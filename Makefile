SCHEME      := OpenUpdater
PROJECT     := OpenUpdater.xcodeproj
CONFIG      := Debug
SWIFT_FORMAT := xcrun swift-format
ICON_SVG    := Design/AppIcon.svg
ICONSET     := OpenUpdater/Assets.xcassets/AppIcon.appiconset
MENUBAR_SVG := Design/MenuBarIcon.svg
MENUBARSET  := OpenUpdater/Assets.xcassets/MenuBarIcon.imageset

.PHONY: build run format clean install-hooks icon manifest recipe-check recipe-download

## build: compile the app (into Xcode's shared DerivedData, so make & Xcode agree)
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

## run: build and launch the same app Xcode produces
run: build
	open "$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2; exit}')/$(SCHEME).app"

## format: format all Swift sources in place
format:
	$(SWIFT_FORMAT) format --in-place --recursive OpenUpdater

## manifest: regenerate OpenUpdater/RecipeManifest.json from the recipes (for runtime sync)
manifest:
	python3 scripts/gen_recipe_manifest.py

## recipe-check: resolve a recipe's latest version using the app's real source logic — ID=<bundle-id> [ARGS='--prereleases']
recipe-check:
	@test -n "$(ID)" || { echo "usage: make recipe-check ID=<bundle-id> [ARGS='--channel esr']"; exit 2; }
	@log=$$(mktemp); swift build --product recipe-check >"$$log" 2>&1 || { cat "$$log"; rm -f "$$log"; exit 1; }; rm -f "$$log"
	@.build/debug/recipe-check $(ID) $(ARGS)

## recipe-download: recipe-check + actually download, extract, and verify the build — ID=<bundle-id>
recipe-download:
	@test -n "$(ID)" || { echo "usage: make recipe-download ID=<bundle-id> [ARGS='--channel esr']"; exit 2; }
	@log=$$(mktemp); swift build --product recipe-check >"$$log" 2>&1 || { cat "$$log"; rm -f "$$log"; exit 1; }; rm -f "$$log"
	@.build/debug/recipe-check $(ID) --download $(ARGS)

## install-hooks: install git hooks via lefthook
install-hooks:
	lefthook install

## icon: rasterize Design/AppIcon.svg into the AppIcon asset catalog (needs rsvg-convert)
icon:
	@command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found — install with: brew install librsvg"; exit 1; }
	rsvg-convert -w 16   -h 16   $(ICON_SVG) -o $(ICONSET)/AppIcon-16.png
	rsvg-convert -w 32   -h 32   $(ICON_SVG) -o $(ICONSET)/AppIcon-16@2x.png
	rsvg-convert -w 32   -h 32   $(ICON_SVG) -o $(ICONSET)/AppIcon-32.png
	rsvg-convert -w 64   -h 64   $(ICON_SVG) -o $(ICONSET)/AppIcon-32@2x.png
	rsvg-convert -w 128  -h 128  $(ICON_SVG) -o $(ICONSET)/AppIcon-128.png
	rsvg-convert -w 256  -h 256  $(ICON_SVG) -o $(ICONSET)/AppIcon-128@2x.png
	rsvg-convert -w 256  -h 256  $(ICON_SVG) -o $(ICONSET)/AppIcon-256.png
	rsvg-convert -w 512  -h 512  $(ICON_SVG) -o $(ICONSET)/AppIcon-256@2x.png
	rsvg-convert -w 512  -h 512  $(ICON_SVG) -o $(ICONSET)/AppIcon-512.png
	rsvg-convert -w 1024 -h 1024 $(ICON_SVG) -o $(ICONSET)/AppIcon-512@2x.png
	rsvg-convert -w 18 -h 18 $(MENUBAR_SVG) -o $(MENUBARSET)/MenuBarIcon-18.png
	rsvg-convert -w 36 -h 36 $(MENUBAR_SVG) -o $(MENUBARSET)/MenuBarIcon-36.png
	@echo "Wrote app icon PNGs to $(ICONSET) and menubar PNGs to $(MENUBARSET)"

## clean: remove build artifacts (incl. the legacy ./build dir)
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) clean
	rm -rf build
