filename := "resume.json"

# Evaluate these variables once when just runs
name := `cat resume.json | yq -r '.basics.name | split(" ") | join("-")'`
commit := `git rev-parse --short HEAD`
pdf_file := "Resume-" + name + "-" + commit + ".pdf"

build:
	zola build

pdf: build
	weasyprint public/resume/index.html {{ pdf_file }}

render: build pdf
	xdg-open {{ pdf_file }} &disown

watch:
	#!/usr/bin/env sh
	inotifywait -m -r . \
		--exclude "(.*\\.pdf$)|public|justfile|\\.git" \
		-e close_write,move,create,delete \
	| while read -r directory events filename; do
		just render
	done
