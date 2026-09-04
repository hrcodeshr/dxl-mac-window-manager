.PHONY: build test package run

build:
	swift build

test:
	swift run DXLSnapCoreCheck

package:
	bash scripts/package-app.sh

run:
	swift run DXLWindowManager
