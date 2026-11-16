#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v clang-format >/dev/null; then
  clang-format -i engine/Scanner.cpp
else
  echo 'clang-format not installed; C++ formatting skipped' >&2
fi
if command -v swift-format >/dev/null; then
  find app -name '*.swift' -print0 | xargs -0 -n 1 swift-format format --in-place
else
  echo 'swift-format not installed; Swift formatting skipped' >&2
fi
