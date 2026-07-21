#!/usr/bin/env bash
# Contract: B01 render-doc plugin core — authoritative docblock in
# plugins/render-doc/README.md ("Contract: B01").
#
# Interface when implemented:
#   render.sh <doc.md> [--open]
# Writes a self-contained sibling .html; --open serves it via the shared
# annotation server (file:// fallback without python3). Exit non-zero with a
# message on stderr for any failure; no output written on failure.
set -euo pipefail

echo "NotImplemented: B01 render-doc plugin core" >&2
exit 1
