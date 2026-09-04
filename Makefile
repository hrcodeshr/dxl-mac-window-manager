.PHONY: build test package

build:
	swift build

test:
	swift run DXLSnapCoreCheck

package:
	bash scripts/package-app.sh
