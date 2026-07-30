.PHONY: build test run install clean

# Docker is the supported toolchain. Host only needs Docker.

build:
	@./scripts/build.sh

test:
	@./scripts/test.sh

run: build
	@./dist/bedrock-linux-gdk.sh

install: build
	@./scripts/install.sh --from ./dist

clean:
	@rm -rf build dist
