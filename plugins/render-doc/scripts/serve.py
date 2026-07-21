#!/usr/bin/env python3
"""Contract: B01 render-doc plugin core — authoritative docblock in
plugins/render-doc/README.md ("Contract: B01").

When implemented: shared single-instance local annotation server. First
render.sh --open starts it, subsequent calls reuse it; serves rendered views
at /d/<id>; composer "Add" POSTs write `@TAG: note` lines into the source
markdown; auto-shutdown after 30 minutes of inactivity."""

raise NotImplementedError("B01 render-doc plugin core")
