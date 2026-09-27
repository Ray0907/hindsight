.PHONY: build install clean

build:
	go build -tags sqlite_fts5 -o hindsight .

install:
	go install -tags sqlite_fts5 .

clean:
	rm -f hindsight
