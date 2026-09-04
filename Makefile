.PHONY: build test package

build:
	swift build

test:
	swift test

package:
	bash scripts/package-app.sh
