BINARY := bin/cursor-recolor
GOFLAGS := -ldflags="-s -w"

.PHONY: all build test clean

all: build

build:
	go build $(GOFLAGS) -o $(BINARY) ./cmd/cursor-recolor

test:
	go test -v ./...

clean:
	rm -rf bin/
