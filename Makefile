SCHEME      := OpenUpdater
PROJECT     := OpenUpdater.xcodeproj
CONFIG      := Debug
DERIVED     := build
SWIFT_FORMAT := xcrun swift-format

.PHONY: build run format clean install-hooks

## build: compile the app
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) build

## run: build and launch the app
run: build
	open "$(DERIVED)/Build/Products/$(CONFIG)/$(SCHEME).app"

## format: format all Swift sources in place
format:
	$(SWIFT_FORMAT) format --in-place --recursive OpenUpdater

## install-hooks: install git hooks via lefthook
install-hooks:
	lefthook install

## clean: remove build artifacts
clean:
	rm -rf $(DERIVED)
