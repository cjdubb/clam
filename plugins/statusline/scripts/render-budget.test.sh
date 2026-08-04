#!/bin/bash
# Functional test for B03 warm-render-budget: the COMPOSITION of context.sh
# (B01) and ccost.sh (B02) into one statusline render. Unlike
# context.test.sh's own §16/§17 (which fake ccost.sh out and use the
# cheapest possible warm scenario -- empty transcript_path, compaction-budget
# env var set), this suite composes the REAL ccost.sh and specifically
# exercises the MANDATORY regression scenario named in the B03 brief:
# transcript file present (adds the idle-age stat call), the
# CLAUDE_CODE_AUTO_COMPACT_WINDOW env var unset with a settings.json present
# (fires the fallback jq), and a worktree cwd with .local (fires the
# .ctx-status.json publish). That is the scenario the B01-only tests never
# measured, and the one the block's ≤10-command contract is actually staked
# on.
# Also covers: the warm render opens nothing under CLAUDE_PROJECTS_DIR and
# never spawns ccost.sh at all (clause 2); a cold render produces the full,
# correct statusline and leaves the segment-bundle cache populated so the
# immediately-following render is warm (clause 3); the plugin.json version
# floor of >= 0.2.0 (clause 4); the README documenting the caching/staleness
# model and its env knobs (clause 5); a fully cold render staying within a
# generous legacy-cost bound (clause 6); and per-session bundle-key isolation
# under a shared cache dir (clause 7). Under B04 context.sh stops invoking
# ccost.sh entirely -- there is no Cost line and no ccost session cache on
# ANY render path, cold or warm -- so clauses 2 and 3 both now assert
# non-invocation rather than the pre-B04 cold-invokes/warm-doesn't split.
# Composition is kept REAL throughout (no fake ccost.sh): a shadow script
# tree symlinks the real context.sh/libs and wraps ccost.sh with a thin
# logging shim that execs the real ccost.sh. Its job has inverted from B03:
# it no longer proves ccost.sh WAS invoked on the cold path, it proves
# ccost.sh is NEVER invoked, on any render path, from outside the render --
# the only way to observe that, since ccost_script is resolved from
# $(dirname "$0"), a path rather than a bare name, so a PATH shim alone
# cannot intercept it.
# Run: bash plugins/statusline/scripts/render-budget.test.sh   (exits non-zero on failure)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$SCRIPT_DIR/context.sh"
CCOST="$SCRIPT_DIR/ccost.sh"
PLUGIN_JSON="$SCRIPT_DIR/../.claude-plugin/plugin.json"
README="$SCRIPT_DIR/../README.md"
source "$SCRIPT_DIR/../lib/platform.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

ESC=$(printf '\033')
strip_ansi() { sed -E "s/${ESC}\\[[0-9;]*m//g"; }

# --- PATH-shim harness: counts external processes the composed render spawns
# One logging wrapper per external binary the renderer may legitimately use,
# each appending its own name to $SHIM_LOG then exec-ing the REAL binary.
# Resolved with `type -P`, NOT `command -v`: this machine's interactive shell
# defines a `grep` shell FUNCTION (aliasing to ugrep via the Claude Code
# CLI), and `command -v grep` returns that function's bare name instead of a
# path in a context where the function is inherited -- which would make the
# generated shim try to `exec grep`, re-entering itself (PATH=$SHIM_BIN only
# during a render) in a fork loop. `type -P` always resolves the real
# on-disk binary, sidestepping functions and aliases entirely.
SHIM_BIN="$TMPROOT/shim-bin"; mkdir -p "$SHIM_BIN"
for _tool in jq git date stat uname mktemp mv cat head tr sed cksum mkdir \
             touch nohup find xargs rm dirname awk grep basename wc cut \
             sort python3; do
  _real=$(type -P "$_tool" 2>/dev/null) || continue
  printf '#!/bin/bash\necho "%s" >> "${SHIM_LOG:-/dev/null}"\nexec "%s" "$@"\n' \
    "$_tool" "$_real" > "$SHIM_BIN/$_tool"
  chmod +x "$SHIM_BIN/$_tool"
done
REAL_BASH=$(type -P bash)

# Shadow script tree: symlinked context.sh + lib (so SCRIPT_DIR/_LIB_DIR
# resolution is untouched, and no pr-status-refresh.sh/git-sync-refresh.sh
# exist there for the cold-path refresh-engine kicks to find -- this plugin
# doesn't ship those two scripts itself, so those kicks never fire regardless)
# alongside a LOGGING WRAPPER around the REAL ccost.sh: it appends its args to
# $CCOST_LOG, then execs the genuine script by absolute path (so ccost.sh's
# own BASH_SOURCE-relative SCRIPT_DIR/PRICES_FILE resolution is unaffected).
# Under B04 context.sh never invokes ccost.sh at all, so this wrapper's job is
# to prove that absence: it is the only way to observe "ccost.sh was NOT
# invoked" from outside (ccost_script is resolved from $(dirname "$0"), a
# path, not a bare name, so a PATH shim alone can't intercept it either way)
# while keeping the composition real.
SHADOW="$TMPROOT/shadow"; mkdir -p "$SHADOW/scripts" "$SHADOW/lib"
ln -s "$CONTEXT" "$SHADOW/scripts/context.sh"
ln -s "$SCRIPT_DIR/../lib/platform.sh" "$SHADOW/lib/platform.sh"
ln -s "$SCRIPT_DIR/../lib/states.sh" "$SHADOW/lib/states.sh"
ln -s "$SCRIPT_DIR/../lib/states.tsv" "$SHADOW/lib/states.tsv"
cat > "$SHADOW/scripts/ccost.sh" <<EOF
#!/bin/bash
echo "\$*" >> "\${CCOST_LOG:-/dev/null}"
exec "$CCOST" "\$@"
EOF
chmod +x "$SHADOW/scripts/ccost.sh"

SHIM_LOG="$TMPROOT/shim.log"
CCOST_LOG_FILE="$TMPROOT/ccost-invocations.log"
REND_OUT="$TMPROOT/rend.out"
REND_ERR="$TMPROOT/rend.err"

# Fake HOME with a settings.json the fallback-jq scenario can read. Never the
# real $HOME -- nothing in this suite may touch the real ~/.claude.
FAKE_HOME="$TMPROOT/fake-home"; mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'EOF'
{"env":{}}
EOF

# render_shim(json, bundle_dir, bundle_ttl, ccost_dir, ccost_ttl,
# projects_dir, [extra_env...]): render through the shadow tree with the
# PATH shim active, every renderer env knob pinned explicitly (never
# inherited). CLAUDE_CODE_AUTO_COMPACT_WINDOW is always left unset (so every
# scenario in this suite exercises the settings.json fallback jq, matching
# the mandatory regression scenario) via `env -i`, which clears the ENTIRE
# environment rather than merging over it -- the strongest hermeticity
# available, since it can't leak a stray CLAUDE_*/CLAM_*/CCOST_* value from
# whatever invoked this test. Clears and repopulates $SHIM_LOG/$CCOST_LOG_FILE
# each call and captures rendered stdout/stderr to fixed files so callers can
# inspect both the process counts and the actual rendered text.
render_shim() { # json bundle_dir bundle_ttl ccost_dir ccost_ttl projects_dir [extra_env...]
  local json="$1" bdir="$2" bttl="$3" cdir="$4" cttl="$5" pdir="$6"; shift 6
  : > "$SHIM_LOG"; : > "$CCOST_LOG_FILE"
  printf '%s' "$json" \
    | env -i PATH="$SHIM_BIN" HOME="$FAKE_HOME" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW= \
        CLAUDE_PROJECTS_DIR="$pdir" \
        CLAM_STATUSLINE_CACHE_DIR="$bdir" CLAM_STATUSLINE_SEGMENT_TTL_SECONDS="$bttl" \
        CCOST_CACHE_DIR="$cdir" CCOST_SESSION_TTL_SECONDS="$cttl" \
        SHIM_LOG="$SHIM_LOG" CCOST_LOG="$CCOST_LOG_FILE" \
        "$@" \
        "$REAL_BASH" "$SHADOW/scripts/context.sh" \
    > "$REND_OUT" 2>"$REND_ERR"
}

# shim_count(log_file, [tool]): total logged invocations, or just $tool's.
shim_count() { # log_file [tool]
  if [ -n "${2:-}" ]; then
    grep -cxF "$2" "$1" 2>/dev/null
  else
    wc -l < "$1" 2>/dev/null | tr -d ' '
  fi
}
# ------------------------------------------------------------------------

# sl_json(cwd, transcript_path): a statusLine JSON payload with model+effort
# set (so the mode/model/effort line renders) and a real context-window pair
# (so the Ctx line renders).
sl_json() { # cwd transcript
  printf '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"workspace":{"current_dir":"%s"},"context_window":{"context_window_size":1000000,"total_input_tokens":145230},"transcript_path":"%s"}' \
    "$1" "$2"
}

# mk_wt(dir): a git worktree with .local, so context.sh's toplevel walk
# resolves and the .ctx-status.json publish path fires.
mk_wt() { # dir
  mkdir -p "$1/.local"
  git -C "$1" init -q >/dev/null 2>&1
}

# mk_transcript(path, input_tokens, model): a one-record assistant JSONL
# transcript ccost.sh can price. requestId/message id are fixed since each
# transcript here is single-record and cost, not dedup behavior, is what's
# under test.
mk_transcript() { # path input_tokens model
  printf '{"type":"assistant","timestamp":"%s","requestId":"r1","message":{"id":"r1","model":"%s","usage":{"input_tokens":%s,"output_tokens":0}}}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$3" "$2" > "$1"
}

# ============================================================================
# Clauses 1, 3, 6 -- one shared scenario, per the brief: the cold render that
# proves clause 3 (correctness + cache seeding) and clause 6 (cold-render
# cost bound) is the exact state the clause-1 warm-budget assertion runs
# against next.
# ============================================================================
MANDATORY_WD="$TMPROOT/mandatory-wd"; mk_wt "$MANDATORY_WD"
MANDATORY_TRANSCRIPT="$TMPROOT/mandatory-transcript.jsonl"
mk_transcript "$MANDATORY_TRANSCRIPT" 1000000 claude-opus-4-8   # -> session cost $5.00
MANDATORY_BUNDLE_DIR="$TMPROOT/mandatory-bundle-cache"
MANDATORY_CCOST_DIR="$TMPROOT/mandatory-ccost-cache"
MANDATORY_PROJECTS_DIR="$TMPROOT/mandatory-projects"; mkdir -p "$MANDATORY_PROJECTS_DIR"
mandatory_json="$(sl_json "$MANDATORY_WD" "$MANDATORY_TRANSCRIPT")"

# --- Clause 3 + 6: cold render -----------------------------------------------
render_shim "$mandatory_json" "$MANDATORY_BUNDLE_DIR" 600 "$MANDATORY_CCOST_DIR" 600 "$MANDATORY_PROJECTS_DIR"
cold_out=$(strip_ansi < "$REND_OUT")
cold_total=$(shim_count "$SHIM_LOG")
cold_ccost_calls=$(shim_count "$CCOST_LOG_FILE")

check "clause3: cold render includes the cwd path" \
  "$(printf '%s' "$cold_out" | grep -qF "$MANDATORY_WD" && echo yes || echo no)" "yes"
check "clause3: cold render includes the model/effort line" \
  "$(printf '%s' "$cold_out" | grep -qF "Opus" && printf '%s' "$cold_out" | grep -qF "high effort" && echo yes || echo no)" "yes"
check "clause3: cold render includes the Ctx-usage line" \
  "$(printf '%s' "$cold_out" | grep -qF "Ctx used:" && echo yes || echo no)" "yes"
check "clause3: cold render includes no Cost line and no Session cost figure" \
  "$(printf '%s' "$cold_out" | grep -qE 'Cost:|Session: \$' && echo yes || echo no)" "no"
check "clause3: cold render seeds exactly one segment-bundle cache entry" \
  "$(find "$MANDATORY_BUNDLE_DIR" -name '*.bundle' 2>/dev/null | wc -l | tr -d ' ')" "1"
check "clause3: cold render seeds zero ccost session cache entries" \
  "$(find "$MANDATORY_CCOST_DIR" -name 'session-*.cache' 2>/dev/null | wc -l | tr -d ' ')" "0"
check "clause3: cold render never spawns ccost.sh" "${cold_ccost_calls:-1}" "0"
# The mandatory scenario's cold render (worktree .local publish, no ccost.sh
# invocation at all under B04) measures 12 external commands today -- down
# from the pre-B04 44, which included three cache-cold ccost.sh scans
# (session/day/week) and their own subprocess forks. 20 keeps proportionally
# comparable headroom over that measured figure (not a brittle exact match)
# while still catching a pathological regression (e.g. an accidental O(n)
# fork loop) -- a regression that reintroduced even one cache-cold ccost.sh
# scan would already blow well past it.
check "clause6: fully cold end-to-end render stays within a generous 20-command legacy-cost bound" \
  "$([ "${cold_total:-999}" -le 20 ] && echo yes || echo no)" "yes"

# --- Clause 1: warm render against exactly that seeded state ----------------
render_shim "$mandatory_json" "$MANDATORY_BUNDLE_DIR" 600 "$MANDATORY_CCOST_DIR" 600 "$MANDATORY_PROJECTS_DIR"
warm_out=$(strip_ansi < "$REND_OUT")
warm_total=$(shim_count "$SHIM_LOG")

check "clause1: warm render (transcript present, no compaction-window env var, worktree .local) invokes at most 10 external commands" \
  "$([ "${warm_total:-999}" -le 10 ] && echo yes || echo no)" "yes"
check "clause1: warm render carries no Cost line (the replayed bundle has no cost_line key)" \
  "$(printf '%s' "$warm_out" | grep -qE 'Cost:|Session: \$' && echo yes || echo no)" "no"

# ============================================================================
# Clause 2 -- warm render opens nothing under CLAUDE_PROJECTS_DIR and never
# spawns ccost.sh. ccost.sh is the ONLY consumer of CLAUDE_PROJECTS_DIR on
# this render path, so "zero ccost.sh invocations" already proves nothing
# under it was opened; the canary-file/listing checks below are a second,
# independent confirmation.
# ============================================================================
C2_WD="$TMPROOT/c2-wd"; mk_wt "$C2_WD"
C2_TRANSCRIPT="$TMPROOT/c2-transcript.jsonl"
mk_transcript "$C2_TRANSCRIPT" 1000000 claude-opus-4-8
C2_BUNDLE_DIR="$TMPROOT/c2-bundle-cache"
C2_CCOST_DIR="$TMPROOT/c2-ccost-cache"
C2_PROJECTS_DIR="$TMPROOT/c2-projects-sentinel"; mkdir -p "$C2_PROJECTS_DIR"
: > "$C2_PROJECTS_DIR/canary.jsonl"
c2_canary_mtime_before=$(clam_mtime_epoch "$C2_PROJECTS_DIR/canary.jsonl")
c2_listing_before=$(find "$C2_PROJECTS_DIR" | sort)
c2_json="$(sl_json "$C2_WD" "$C2_TRANSCRIPT")"

render_shim "$c2_json" "$C2_BUNDLE_DIR" 600 "$C2_CCOST_DIR" 600 "$C2_PROJECTS_DIR"   # cold: seeds the bundle
render_shim "$c2_json" "$C2_BUNDLE_DIR" 600 "$C2_CCOST_DIR" 600 "$C2_PROJECTS_DIR"   # warm: measure
c2_ccost_calls=$(shim_count "$CCOST_LOG_FILE")
c2_canary_mtime_after=$(clam_mtime_epoch "$C2_PROJECTS_DIR/canary.jsonl")
c2_listing_after=$(find "$C2_PROJECTS_DIR" | sort)

check "clause2: warm render never spawns ccost.sh" "${c2_ccost_calls:-1}" "0"
check "clause2: warm render creates no new entries under CLAUDE_PROJECTS_DIR" \
  "$c2_listing_after" "$c2_listing_before"
check "clause2: warm render leaves the sentinel canary file's mtime untouched" \
  "$c2_canary_mtime_after" "$c2_canary_mtime_before"

# ============================================================================
# Clause 4 -- plugin.json version floor. The exact version isn't the point:
# the caching change must ship WITH a version bump (so version-keyed plugin
# caches surface it), so this checks the version is a well-formed semver
# no lower than 0.2.0 rather than pinning to that exact string -- a later
# bump for unrelated reasons must not make this clause regress.
# ============================================================================
plugin_version="$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)"
check "clause4: plugin.json version is >= 0.2.0 (caching bump landed)" \
  "$([[ "$plugin_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
     && [[ "$(printf '0.2.0\n%s\n' "$plugin_version" | sort -V | head -n1)" == "0.2.0" ]] \
     && echo yes || echo no)" "yes"

# ============================================================================
# Clause 5 -- README documents the caching/staleness model (segment bundle
# 5s, session cost 30s, day/week 300s) and the three env knobs, in PROSE
# outside the HTML contract comments. Substantive-content check (knob names
# + the actual TTL figures present somewhere in the non-comment body), not an
# exact-wording match. Comment-stripping is a simple line-level state
# machine: valid here because every HTML comment in this README opens and
# closes on its own line (no inline single-line comments share a line with
# prose elsewhere in the file).
# ============================================================================
readme_prose() {
  awk '
    /<!--/ { incomment=1; next }
    incomment && /-->/ { incomment=0; next }
    incomment { next }
    { print }
  ' "$README"
}
readme_body="$(readme_prose)"

check "clause5: README documents the CLAM_STATUSLINE_CACHE_DIR knob outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qF 'CLAM_STATUSLINE_CACHE_DIR' && echo yes || echo no)" "yes"
check "clause5: README documents the CLAM_STATUSLINE_SEGMENT_TTL_SECONDS knob outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qF 'CLAM_STATUSLINE_SEGMENT_TTL_SECONDS' && echo yes || echo no)" "yes"
check "clause5: README documents the CCOST_SESSION_TTL_SECONDS knob outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qF 'CCOST_SESSION_TTL_SECONDS' && echo yes || echo no)" "yes"
check "clause5: README documents the 5s segment-bundle TTL figure outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qE '\b5\b' && echo yes || echo no)" "yes"
check "clause5: README documents the 30s session-cost TTL figure outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qE '\b30\b' && echo yes || echo no)" "yes"
check "clause5: README documents the 300s day/week TTL figure outside the contract comment" \
  "$(printf '%s' "$readme_body" | grep -qE '\b300\b' && echo yes || echo no)" "yes"

# ============================================================================
# Clause 7 -- per-session bundle KEYING: two renders sharing a cwd (and cache
# dir) but with different transcript_paths must still land in two distinct
# bundle cache entries, i.e. the cache key is session-scoped rather than just
# cwd-scoped, even though nothing in the bundle's own payload is session-
# derived. What this clause does NOT assert, post-B04: payload divergence
# between those two entries. Session cost used to be the observable that
# proved cross-session isolation (session A's warm render would never serve
# session B's cost), but B04 removes cost_line from the bundle entirely, and
# the five keys that remain -- branch, pr_badge, git_sync_segment,
# state_segment, clam_mode -- are all cwd-derived. Two sessions sharing a cwd
# therefore now produce byte-identical bundle payloads by construction, so
# there is no payload-divergence observable left to assert here; manufacturing
# one would not be testing anything real. The surviving check below is the
# one still-true half of the old invariant: the cache key itself stays
# session-scoped.
# ============================================================================
ISO_WD="$TMPROOT/iso-wd"; mk_wt "$ISO_WD"
ISO_BUNDLE_DIR="$TMPROOT/iso-bundle-cache"
ISO_CCOST_DIR="$TMPROOT/iso-ccost-cache"
ISO_PROJECTS_DIR="$TMPROOT/iso-projects"; mkdir -p "$ISO_PROJECTS_DIR"
ISO_TRANSCRIPT_A="$TMPROOT/iso-transcript-a.jsonl"
ISO_TRANSCRIPT_B="$TMPROOT/iso-transcript-b.jsonl"
mk_transcript "$ISO_TRANSCRIPT_A" 1000000 claude-opus-4-8   # distinct transcript_path from B (dollar figure no longer observable)
mk_transcript "$ISO_TRANSCRIPT_B" 2000000 claude-opus-4-8   # distinct transcript_path from A (dollar figure no longer observable)
iso_json_a="$(sl_json "$ISO_WD" "$ISO_TRANSCRIPT_A")"
iso_json_b="$(sl_json "$ISO_WD" "$ISO_TRANSCRIPT_B")"

render_shim "$iso_json_a" "$ISO_BUNDLE_DIR" 600 "$ISO_CCOST_DIR" 600 "$ISO_PROJECTS_DIR"   # cold: seeds session A's bundle
render_shim "$iso_json_b" "$ISO_BUNDLE_DIR" 600 "$ISO_CCOST_DIR" 600 "$ISO_PROJECTS_DIR"   # cold: seeds session B's bundle (same cwd, same cache dir)

check "clause7: two sessions sharing a cwd and cache dir produce two distinct bundle entries" \
  "$(find "$ISO_BUNDLE_DIR" -name '*.bundle' 2>/dev/null | wc -l | tr -d ' ')" "2"

if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
