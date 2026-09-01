#!/bin/bash
# Geometry tests: build main.swift with the tap replaced by tests/spans.swift's
# entry point, then run it. No display, pointer or Accessibility grant needed.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -DCURSORWRAP_TESTS -o "$out/cursorwrap-tests" main.swift tests/spans.swift
"$out/cursorwrap-tests"
