#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
if command -v swiftc >/dev/null; then
  swiftc -frontend -parse app/Models/*.swift app/Services/*.swift app/ViewModels/*.swift app/Views/*.swift
fi
