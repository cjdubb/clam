#!/usr/bin/env bash
# hostname-docs.test.sh — the prose-and-version block of plan
# 002-discovery-landing-dns ("Contract: 002-B08 G03 docs + bump", the HTML
# comment near the end of plugins/render-doc/README.md).
#
# The server grows three new names it will answer to, and one of them —
# "<label>.localhost:27183" — is the reason the block exists: a readable,
# per-worktree address that needs no registration anywhere. A reader who is
# never told about it will keep typing the IP, so the capability is worth
# exactly as much as its documentation. Two audiences have to learn it: a
# reader of the plugin README, and a reader of serve.py's own header prose.
#
# What has to be said is unusually specific, because the honest answer is
# conditional. Chrome and Firefox resolve *.localhost to loopback themselves,
# on Linux and macOS alike, with nothing to set up. Safari and curl defer to
# the system resolver, which on macOS wants one /etc/hosts line — and that line
# is an OPTIONAL enhancement, never a prerequisite, because the core capability
# is the 127.0.0.1 address that has always worked. So the checks below anchor
# the SUPPORT MATRIX (both browsers, both other clients, both operating
# systems) and the OPTIONALITY of the hosts line as separate facts, and pair
# them with a negative: the Getting started section must not grow a setup step.
#
# Prose is asserted by presence/proximity anchors drawn from the contract's own
# vocabulary, never by exact sentences: the wording is the implementer's
# choice. That is the convention workgraph-docs.test.sh established for this
# plugin's docs blocks and serve-mode-docs.test.sh, discovery-docs.test.sh and
# landing-docs.test.sh continued, including the discovered-from-the-tree
# sibling-plugin check.
#
# Scoping is what makes these checks mean anything. The README's "### Scripts"
# section ALREADY describes the server, its port and its Host pinning, so a
# section-wide grep for "Host" or "port" would go green today on prose that
# never mentions a hostname. Every fact below is therefore asserted inside the
# text immediately surrounding a HOSTNAME mention ("localhost", ".localhost",
# "[::1]") — and every one of those anchor strings is absent from both files
# today, which is what makes the windows honest.
#
# Marker note: plan-002 contract markers are plan-qualified. serve.py carries
# bare "Contract: B<NN>" markers from earlier plans meaning something else, so
# every marker check here uses the full 002-B08 form and nothing greps the bare
# one. serve.py's header prose is read as its module DOCSTRING specifically,
# extracted with ast — the 002-B07 contract comment lower in that file quotes
# every string this suite looks for, and a whole-file grep would go green on it
# and red again the moment it is deleted at acceptance.
#
# Deliberately NOT asserted here, because another suite already gates it: the
# README "## Tests" list naming every shipped suite (server-docs.test.sh
# derives that list from the tree), README template conformance (readme-lint),
# and whether the new prose is TRUE — hostname-allowlist.test.sh and
# dual-bind.test.sh gate the behaviour it describes.

set -uo pipefail # deliberately no -e: one failed check must not abort the rest

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
README="$PLUGIN_DIR/README.md"
SERVE="$SCRIPT_DIR/serve.py"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
ROOT_README="$REPO_ROOT/README.md"

# The version this block bumps to, asserted as a FLOOR rather than an equality:
# a later plan will bump the plugin again, and a test about hostname docs must
# not go red the day that lands. Repo precedent: landing-docs.test.sh,
# discovery-docs.test.sh and workgraph-docs.test.sh's own de-pinned floors.
VERSION_FLOOR='0.10.0'

# How much text either side of an anchor counts as documenting it. Wide enough
# for a paragraph that states several facts at once, narrow enough that an
# unrelated neighbouring paragraph cannot satisfy a clause on its own.
WINDOW=400

# A tighter window for the two facts that must sit BESIDE the thing they
# qualify rather than merely in the same paragraph: the hosts line's
# optionality, and the port beside a hostname.
NEAR=160

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}
pass() {
  printf 'PASS  %s\n' "$*"
}

# --- Helpers -----------------------------------------------------------------

# Contract prose quotes the very strings these checks look for, so every prose
# check runs against a copy with HTML comments removed — otherwise the checks
# would go green while the contract comment is still there and red again the
# moment it is deleted at acceptance. Precedent: workgraph-docs.test.sh.
strip_docblocks() { sed '/<!--/,/-->/d' "$1"; }

# The README is hard-wrapped and every check below is a proximity check, so
# each region is flattened to one line first. A two-word pattern must not miss
# because the author's line broke between the words.
flatten() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'; }

# Not `grep -q`: under `set -o pipefail` an early-exiting grep -q closes the
# pipe under a still-writing printf and the SIGPIPE becomes the pipeline's
# status. Cheap to avoid, invisible when it bites. (graph-always-docs.test.sh
# documents the same trap.)
matches() { # <haystack> <ERE>
  printf '%s\n' "$1" | grep -iE -- "$2" > /dev/null 2>&1
}
matches_f() { # <haystack> <literal>
  printf '%s\n' "$1" | grep -iF -- "$2" > /dev/null 2>&1
}
has() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
has_f() { # <haystack> <literal> <label>
  if matches_f "$1" "$2"; then pass "$3"; else fail "$3"; fi
}
lacks() { # <haystack> <ERE> <label>
  if matches "$1" "$2"; then fail "$3"; else pass "$3"; fi
}

section() { # <file> <heading-ere> <stop-ere>
  awk -v pat="$2" -v stop="$3" '
    /^(```|~~~)/ { fence = !fence; if (p) print; next }
    !p { if (!fence && $0 ~ pat) p = 1; next }
    p && !fence && $0 ~ stop { exit }
    p
  ' "$1"
}

# Sibling plugin directory names, discovered from the tree rather than
# hardcoded — a literal "<name> plugin"/"/<name>:"/"<name>@clam"/"plugins/
# <name>/" string in this file's own source would itself be a cross-plugin
# reference and get flagged by architecture-lint. Copied from
# landing-docs.test.sh, which copied it from discovery-docs.test.sh.
sibling_plugins() {
  find "$REPO_ROOT/plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2> /dev/null \
    | grep -vFx "$(basename "$PLUGIN_DIR")" | sort
}

assert_no_sibling_reference() { # <haystack> <label>
  local haystack="$1" label="$2"
  local hit="" p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if matches "$haystack" "/${p}:|${p}@clam|plugins/${p}/|${p}[[:space:]]plugin"; then
      hit="$p"
      break
    fi
  done < <(sibling_plugins)
  if [ -n "$hit" ]; then
    fail "$label: names a sibling plugin (reference form found — see CLAUDE.md's layering rule)"
  else
    pass "$label: names no sibling plugin"
  fi
}

# The text around every anchor mention in a region. Empty when the feature is
# not documented at all, which is what keeps every fact check honest: no
# mention, no window, no accidental pass from a neighbour.
#
# The obvious spelling of this — `grep -oEi ".{0,$WINDOW}($2).{0,$WINDOW}"` —
# is correct but pathologically slow once the anchor actually matches: on a
# region flattened to one ~20KB line grep expands a DFA state per (start
# offset x window length) pair, and a handful of windowed anchors take minutes
# rather than the seconds this suite is allowed. Finding the anchor and slicing
# either side of it is the same answer in linear time. (landing-docs.test.sh
# documents the same measurement.)
window_around() { # <flattened region> <anchor ERE> [width]
  ANCHOR="$2" ANCHOR_WINDOW="${3:-$WINDOW}" python3 -c '
import os
import re
import sys

data = sys.stdin.read()
width = int(os.environ["ANCHOR_WINDOW"])
spans = [
    data[max(0, m.start() - width):m.end() + width]
    for m in re.finditer(os.environ["ANCHOR"], data, re.I)
]
sys.stdout.write(" ".join(spans))
' <<< "$1" 2> /dev/null
}

# --- Vocabulary ---------------------------------------------------------------
# Each fact as an alternation, so a faithful rewrite is not forced into one
# word. $WS spells a gap that survives a hard wrap flattened to one space.
WS='[[:space:]]+'

# The anchor. Measured at zero occurrences in the comment-stripped README and
# in serve.py's docstring today, which is exactly why the window it defines is
# empty until this block writes something.
HOSTNAME='localhost|\[::1\]'

# The friendly form itself, and the port that must travel with it.
LABEL_FORM='\.localhost'
PORT_FACT='27183|RENDER_DOC_PORT|<port>|:\{?port'
# The two other names the block documents alongside it.
V6_LITERAL='\[::1\]'
# The support matrix, as four clients and two operating systems.
CHROME='chrome|chromium'
FIREFOX='firefox'
SAFARI='safari'
CURL='curl'
LINUX='linux'
MACOS='macos|mac os|os x|darwin'
# Zero setup, for the browsers that resolve the name themselves.
ZERO_SETUP="zero${WS}(setup|config)|no${WS}(setup|configuration|config)|nothing${WS}to${WS}(set${WS}up|configure)|without${WS}(any${WS})?(setup|configuration)|automatic|themselves|out${WS}of${WS}the${WS}box|works${WS}as${WS}is"
# The system resolver, for the clients that do not.
RESOLVER="resolver|resolution|resolves?|/etc/hosts|dns"
HOSTS_FILE='/etc/hosts'
# Optionality: the hosts line is an enhancement, never a prerequisite.
OPTIONAL="optional|not${WS}required|never${WS}required|no${WS}need|only${WS}(if|needed|when)|enhancement|if${WS}you${WS}want"
# Why it is safe without registering anything.
RFC='6761|special[- ]use|reserved'
REBIND="rebind|rebinding|loopback${WS}only|only${WS}(ever${WS})?(reach|resolve)|never${WS}leaves|cannot${WS}(reach|resolve|leave)"

# --- Regions ------------------------------------------------------------------

README_BODY="$WORK/README.stripped.md"
strip_docblocks "$README" > "$README_BODY"

if [ ! -s "$README_BODY" ]; then
  fail "setup: the stripped copy of README.md came out empty — no clause could be checked"
  printf 'hostname-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
pass "setup: README.md stripped of its HTML comments"

# The strip is what makes every check below meaningful. Prove it worked rather
# than assuming it: any plan-002 contract comment present in the raw file must
# be absent from the stripped copy. Pinned to no single block id — once every
# 002 comment is gone a check naming only one would be vacuously green, which
# is exactly when the strip stops being proven, so that case reports itself.
if ! grep -qE 'Contract: 002-B[0-9]+' "$README"; then
  pass "sanity: no plan-002 contract comment remains in the raw README to prove the strip against"
elif grep -qE 'Contract: 002-B[0-9]+' "$README_BODY"; then
  fail "sanity: a plan-002 contract comment survived the strip — the sed range needs adjusting"
else
  pass "sanity: plan-002 contract comments are stripped from the body"
fi

readme_expect="$(section "$README_BODY" '^## What to expect$' '^## ' | flatten)"
readme_scripts="$(section "$README_BODY" '^### Scripts$' '^### ' | flatten)"
readme_workflows="$(section "$README_BODY" '^## Common workflows$' '^## ' | flatten)"
readme_failmodes_raw="$(section "$README_BODY" '^### Failure modes$' '^### ')"
readme_failmodes="$(printf '%s\n' "$readme_failmodes_raw" | flatten)"
readme_uninstall="$(section "$README_BODY" '^## Uninstalling$' '^## ' | flatten)"

# The homes this contract's audience reads, taken as one region: which of them
# carries which sentence is the implementer's call, that all of it is said is
# the contract's.
readme_region="$readme_expect $readme_workflows $readme_scripts $readme_failmodes $readme_uninstall"

# serve.py's "header prose" is its module docstring, and only that. The
# 002-B07 contract COMMENT lower in the same file quotes every string checked
# below and is deleted at acceptance, so a whole-file read would be green for
# the wrong reason today and red for the wrong reason tomorrow.
SERVE_DOC="$WORK/serve.docstring.txt"
python3 - "$SERVE" > "$SERVE_DOC" 2> "$WORK/ast.err" << 'PY'
import ast
import sys

with open(sys.argv[1], encoding='utf-8') as fh:
    src = fh.read()
doc = ast.get_docstring(ast.parse(src)) or ''
sys.stdout.write(doc)
PY
serve_doc="$(flatten < "$SERVE_DOC")"

if [ -z "$serve_doc" ]; then
  fail "setup: serve.py's module docstring could not be read -- $(tail -2 "$WORK/ast.err" 2> /dev/null | tr '\n' ' ')"
else
  pass "setup: serve.py's module docstring extracted (the file's header prose)"
fi

# =============================================================================
# Acceptance signal: this block's own contract comment is gone. Read RAW, on
# purpose — this is the one assertion the strip would defeat.
# =============================================================================

if grep -qF 'Contract: 002-B08' "$README"; then
  fail "README.md: the 'Contract: 002-B08' comment is still present (deleting it is part of the work)"
else
  pass "README.md: the 'Contract: 002-B08' comment is removed"
fi

# =============================================================================
# Clause: the README documents the friendly hostname
# =============================================================================

if [ -z "$readme_scripts" ]; then
  fail "README: the '### Scripts' section could not be located"
else
  pass "README: the '### Scripts' section is present"
fi
if [ -z "$readme_expect" ]; then
  fail "README: the '## What to expect' section could not be located"
else
  pass "README: the '## What to expect' section is present"
fi

readme_host="$(window_around "$readme_region" "$HOSTNAME")"

if [ -z "$readme_region" ]; then
  fail "README: none of the documenting sections could be located — no hostname clause can be checked"
elif [ -z "$readme_host" ]; then
  fail "README: a friendly hostname is never mentioned in the sections that document the server"
  fail "README: names the <label>.localhost form"
  fail "README: names the port that travels with the hostname"
  fail "README: names the [::1] literal as an accepted name"
  fail "README: names Chrome as resolving *.localhost itself"
  fail "README: names Firefox as resolving *.localhost itself"
  fail "README: states that those browsers need no setup"
  fail "README: names Safari as following the system resolver"
  fail "README: names curl as following the system resolver"
  fail "README: names the system resolver as what the other clients follow"
  fail "README: states the matrix OS-neutrally — names Linux"
  fail "README: states the matrix OS-neutrally — names macOS"
  fail "README: documents the /etc/hosts line"
  fail "README: says why the scheme is rebinding-safe"
  fail "README: cites RFC 6761 / special-use names as the reason"
else
  pass "README: the friendly hostname is documented in the sections that own the server"
  has "$readme_host" "$LABEL_FORM" "README: names the <label>.localhost form"
  has "$readme_host" "$V6_LITERAL" "README: names the [::1] literal as an accepted name"
  has "$readme_host" "$CHROME" "README: names Chrome as resolving *.localhost itself"
  has "$readme_host" "$FIREFOX" "README: names Firefox as resolving *.localhost itself"
  has "$readme_host" "$ZERO_SETUP" "README: states that those browsers need no setup"
  has "$readme_host" "$SAFARI" "README: names Safari as following the system resolver"
  has "$readme_host" "$CURL" "README: names curl as following the system resolver"
  has "$readme_host" "$RESOLVER" "README: names the system resolver as what the other clients follow"
  has "$readme_host" "$LINUX" "README: states the matrix OS-neutrally — names Linux"
  has "$readme_host" "$MACOS" "README: states the matrix OS-neutrally — names macOS"
  has_f "$readme_host" "$HOSTS_FILE" "README: documents the /etc/hosts line"
  has "$readme_host" "$REBIND" "README: says why the scheme is rebinding-safe"
  has "$readme_host" "$RFC" "README: cites RFC 6761 / special-use names as the reason"
  assert_no_sibling_reference "$readme_host" "README hostname prose"

  # The port has to travel WITH the name: "clam.localhost" on its own is an
  # address that does not work, and a reader who copies it gets a 403. Checked
  # in a tight window around the .localhost form specifically, not around the
  # whole hostname anchor, so the port sentence three paragraphs up cannot
  # satisfy it.
  readme_labelform="$(window_around "$readme_region" "$LABEL_FORM" "$NEAR")"
  if [ -z "$readme_labelform" ]; then
    fail "README: names the port beside the <label>.localhost form"
  else
    has "$readme_labelform" "$PORT_FACT" "README: names the port beside the <label>.localhost form"
  fi
fi

# =============================================================================
# Invariant: no sudo, no system change, ever a prerequisite — the hosts line is
# documented as an optional enhancement only
# =============================================================================

readme_hosts="$(window_around "$readme_region" "$HOSTS_FILE" "$NEAR")"
if [ -z "$readme_hosts" ]; then
  fail "README: the /etc/hosts line is never mentioned, so its optionality cannot be stated"
  fail "README: marks the /etc/hosts line OPTIONAL"
  fail "README: says which client and OS combination the hosts line is for"
else
  pass "README: the /etc/hosts line is mentioned"
  has "$readme_hosts" "$OPTIONAL" "README: marks the /etc/hosts line OPTIONAL"
  has "$readme_hosts" "$MACOS|$SAFARI|$CURL|$RESOLVER" \
    "README: says which client and OS combination the hosts line is for"
fi

# The strongest available check on "never a prerequisite" is structural rather
# than lexical: negated prose ("no /etc/hosts line is required") and required
# prose ("an /etc/hosts line is required") share their vocabulary, so a word
# search cannot tell them apart. Where they DO differ is placement — a genuine
# prerequisite belongs in Getting started, and an optional enhancement never
# does. So Getting started must stay free of both the hosts file and sudo.
readme_start="$(section "$README_BODY" '^## Getting started$' '^## ' | flatten)"
if [ -z "$readme_start" ]; then
  fail "README: the '## Getting started' section could not be located"
else
  pass "README: the '## Getting started' section is present"
  lacks "$readme_start" "$HOSTS_FILE" \
    "README Getting started: no /etc/hosts step (no system change is a prerequisite)"
  lacks "$readme_start" 'sudo' \
    "README Getting started: no sudo step (no privileged action is a prerequisite)"
fi

# The core capability is the address that has always worked, and it must still
# be documented as the thing that needs nothing: a README that presented the
# hostname as the only way in would have made a system change a prerequisite by
# omission.
if [ -n "$readme_scripts" ]; then
  has_f "$readme_scripts" '127.0.0.1' \
    "README Scripts: the 127.0.0.1 address is still documented as an accepted name"
fi

# =============================================================================
# Clause: serve.py's header prose names the hostname support too
# =============================================================================

if [ -z "$serve_doc" ]; then
  fail "serve.py docstring: the friendly hostname is undocumented (no docstring could be read)"
  fail "serve.py docstring: names the <label>.localhost form"
  fail "serve.py docstring: names the port or the port variable"
  fail "serve.py docstring: says the accepted names all reach loopback"
else
  serve_host="$(window_around "$serve_doc" "$HOSTNAME")"
  if [ -z "$serve_host" ]; then
    fail "serve.py docstring: the friendly hostname is never mentioned in the file's header prose"
    fail "serve.py docstring: names the <label>.localhost form"
    fail "serve.py docstring: names the port or the port variable"
    fail "serve.py docstring: says the accepted names all reach loopback"
  else
    pass "serve.py docstring: the friendly hostname is documented in the file's header prose"
    has "$serve_host" "$LABEL_FORM" "serve.py docstring: names the <label>.localhost form"
    has "$serve_host" "$PORT_FACT" "serve.py docstring: names the port or the port variable"
    has "$serve_host" "$REBIND|$RFC" "serve.py docstring: says the accepted names all reach loopback"
    assert_no_sibling_reference "$serve_host" "serve.py docstring hostname prose"
  fi
fi

# =============================================================================
# Invariant: this block adds prose, it does not rewrite what is already there.
# The facts pinned below belong to earlier blocks and have no reason to move.
# =============================================================================

if [ -n "$readme_scripts" ]; then
  if matches "$readme_scripts" '27183' && matches "$readme_scripts" 'RENDER_DOC_PORT'; then
    pass "README Scripts: the fixed port and its override are still documented"
  else
    fail "README Scripts: the fixed port or the RENDER_DOC_PORT override was lost"
  fi
  has_f "$readme_scripts" '/docs.json' "README Scripts: the /docs.json route is still documented"
  has_f "$readme_scripts" '/project/' "README Scripts: the worktree landing page route is still documented"
  has "$readme_scripts" 'render-doc-registry' \
    "README Scripts: the registry's /tmp file, keyed by port, is still documented"
  has_f "$readme_scripts" 'unserved' \
    "README Scripts: the index's filesystem discovery is still documented"
  # The rejection half of the Host rule survives the widening: naming more
  # accepted forms must not read as dropping the check.
  has "$readme_scripts" "reject|refus|403|denied|not${WS}accepted" \
    "README Scripts: a Host outside the accepted set is still documented as rejected"
fi
if [ -n "$readme_failmodes" ]; then
  if matches "$readme_failmodes" '\-\-serve' && matches "$readme_failmodes" '/raw'; then
    pass "README Failure modes: the existing --serve and /raw rows survive"
  else
    fail "README Failure modes: an existing failure-mode row was lost"
  fi
  has_f "$readme_failmodes" '/project/' \
    "README Failure modes: the landing-page row survives"
fi

# =============================================================================
# Clause: the version legs
# =============================================================================

if ! command -v jq > /dev/null 2>&1; then
  fail "jq not found — the version legs cannot be checked"
else
  pj_version="$(jq -r '.version' "$PLUGIN_JSON" 2> /dev/null)"
  if [ -z "$pj_version" ] || [ "$pj_version" = "null" ]; then
    fail "plugin.json: version missing or unparseable"
  elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "$pj_version" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
    pass "plugin.json: version is $pj_version (>= $VERSION_FLOOR)"
  else
    fail "plugin.json: version is '$pj_version', expected $VERSION_FLOOR or later"
  fi

  # Byte-exact description: this block bumps the version, it does not restate
  # what the plugin is.
  EXPECTED_DESC='Render a planning or decision markdown file into a single self-contained dark-theme HTML view, with an annotation server whose in-page composer writes @TAG: feedback lines back into the source markdown.'
  pj_desc="$(jq -r '.description' "$PLUGIN_JSON" 2> /dev/null)"
  if [ "$pj_desc" = "$EXPECTED_DESC" ]; then
    pass "plugin.json: description byte-unchanged"
  else
    fail "plugin.json: description changed (expected byte-unchanged)"
  fi

  # Anchored on the render-doc row so a sibling plugin's row can never satisfy
  # it. readme-lint pairs this cell with plugin.json, so both legs are pinned:
  # the floor (this block's bump actually happened) and the agreement (the two
  # never drift apart).
  root_row="$(grep -E '^\| *\[render-doc\]\(plugins/render-doc/\) *\|' "$ROOT_README" || true)"
  if [ -z "$root_row" ]; then
    fail "root README: the render-doc plugins-table row was not found — the version cell cannot be checked"
  else
    pass "root README: the render-doc plugins-table row is present"
    root_row_version="$(printf '%s' "$root_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -z "$root_row_version" ]; then
      fail "root README: the render-doc row has no vX.Y.Z version cell"
    elif [ "$(printf '%s\n%s\n' "$VERSION_FLOOR" "${root_row_version#v}" | sort -V | head -1)" = "$VERSION_FLOOR" ]; then
      pass "root README: the render-doc row version is $root_row_version (>= v$VERSION_FLOOR)"
    else
      fail "root README: the render-doc row version is '$root_row_version', expected v$VERSION_FLOOR or later"
    fi
    if [ "$root_row_version" = "v$pj_version" ]; then
      pass "root README: the render-doc row version $root_row_version matches plugin.json"
    else
      fail "root README: the render-doc row version is '${root_row_version:-missing}', expected v$pj_version to match plugin.json"
    fi
    if matches_f "$root_row" '✅'; then
      pass "root README: the render-doc row keeps the ✅ status marker"
    else
      fail "root README: the render-doc row lost the ✅ status marker"
    fi
  fi
fi

# =============================================================================
# Left to acceptance review
# =============================================================================
# Whether the matrix is genuinely OS-NEUTRAL is a reading, not a grep: these
# anchors prove both operating systems and all four clients are named in the
# same breath as the hostname, not that the sentence attributes the difference
# to the client rather than to the OS — which is the actual claim. Likewise
# "why this is rebinding-safe in ONE sentence" is a length and clarity
# judgement no assertion should make. And whether serve.py's own "Contract:
# B01" docblock — which still states the superseded exact-match Host rule —
# should be amended alongside the header prose is the orchestrator's call: it
# belongs to an earlier plan, and this suite deliberately asserts nothing
# about it.

# --- Summary ------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  printf 'hostname-docs.test.sh: %d assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'hostname-docs.test.sh: all assertions passed\n'
