.PHONY: build install clean release

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X main.version=$(VERSION)

build:
	go build -tags sqlite_fts5 -ldflags "$(LDFLAGS)" -o hindsight .

install:
	go install -tags sqlite_fts5 -ldflags "$(LDFLAGS)" .

# macOS only for now (Phase 1). cgo, so each arch is built with clang's -arch.
release:
	rm -rf dist && mkdir -p dist
	for arch in arm64 amd64; do \
	  clangarch=$$arch; [ $$arch = amd64 ] && clangarch=x86_64; \
	  CGO_ENABLED=1 GOOS=darwin GOARCH=$$arch CC="clang -arch $$clangarch" \
	    go build -trimpath -tags sqlite_fts5 -ldflags "$(LDFLAGS)" -o dist/hindsight . && \
	  cp LICENSE README.md dist/ && \
	  tar -C dist -czf dist/hindsight_$(VERSION)_darwin_$$arch.tar.gz hindsight LICENSE README.md && \
	  rm dist/hindsight dist/LICENSE dist/README.md || exit 1; \
	done
	cd dist && shasum -a 256 *.tar.gz > SHA256SUMS

clean:
	rm -rf hindsight dist
