.PHONY: build run clean

build:
	bash scripts/build-app.sh

run: build
	open build/PressStream.app

clean:
	rm -rf .build build
