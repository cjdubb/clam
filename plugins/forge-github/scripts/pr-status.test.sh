#!/bin/bash
# Functional test for pr-status.sh — pins the `state` field mapping.
# Run: bash plugins/forge-github/scripts/pr-status.test.sh   (exits non-zero on failure)
#
# No network: `gh` is replaced by a shim on PATH that serves canned JSON from
# $TMPROOT. Cases 4 and 5 guard the closed-PR mapping — a PR closed while a
# draft, and a plain closed PR, must both map to "CLOSED" (consumers match
# state == "CLOSED" exactly), not "Draft".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TMPROOT=$(mktemp -d)

FAILED=0
check() { # label got expected
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 -> got '$2', expected '$3'"; FAILED=1
  fi
}

# --- gh shim: dispatch on args, serve canned JSON from $TMPROOT ---
mkdir -p "$TMPROOT/bin"
cat > "$TMPROOT/bin/gh" <<SHIM
#!/bin/bash
# \$1 is the gh subcommand group (pr / api / repo).
case "\$1" in
  pr)
    # gh pr view <N> --repo test/repo --json ...  -> identifier is \$3
    cat "$TMPROOT/pr-\$3.json"
    ;;
  api)
    # gh api graphql ... -F number=<N> ...  -> find the number=<N> arg
    num=""
    for a in "\$@"; do
      case "\$a" in number=*) num="\${a#number=}" ;; esac
    done
    if [[ -f "$TMPROOT/gql-\$num.json" ]]; then
      cat "$TMPROOT/gql-\$num.json"
    else
      echo '{"data":{"repository":{"pullRequest":{"mergeQueueEntry":null,"reviewThreads":{"nodes":[]}}}}}'
    fi
    ;;
  repo)
    # Defensive: the test always passes --repo test/repo, so this is unused.
    echo '{"owner":{"login":"test"},"name":"repo"}'
    ;;
esac
exit 0
SHIM
chmod +x "$TMPROOT/bin/gh"
export PATH="$TMPROOT/bin:$PATH"

# --- canned PR objects: every field gh pr view --json requests / jq reads ---
# KEEP .number == N so the graphql lookup keys (gql-<N>.json) line up.
pr_json() { # number state isDraft
  jq -n --argjson n "$1" --arg st "$2" --argjson dr "$3" '
    {number: $n, title: "t", url: ("https://example/" + ($n | tostring)),
     state: $st, isDraft: $dr,
     reviewDecision: null, reviewRequests: [], reviews: [],
     statusCheckRollup: [], author: {login: "someone"},
     additions: 0, deletions: 0,
     mergeable: "MERGEABLE", mergeStateStatus: "CLEAN"}'
}

pr_json 1 OPEN   false > "$TMPROOT/pr-1.json"
pr_json 2 OPEN   true  > "$TMPROOT/pr-2.json"
pr_json 3 MERGED false > "$TMPROOT/pr-3.json"
pr_json 4 CLOSED true  > "$TMPROOT/pr-4.json"
pr_json 5 CLOSED false > "$TMPROOT/pr-5.json"
pr_json 6 OPEN   false > "$TMPROOT/pr-6.json"
pr_json 7 OPEN   false > "$TMPROOT/pr-7.json"

# --- graphql overrides for the queue cases (full shape) ---
gql_json() { # mergeQueueEntry-json
  jq -n --argjson e "$1" '
    {data: {repository: {pullRequest:
      {mergeQueueEntry: $e, reviewThreads: {nodes: []}}}}}'
}
gql_json '{"state":"QUEUED","position":1}' > "$TMPROOT/gql-6.json"
gql_json '{"state":"UNMERGEABLE"}'         > "$TMPROOT/gql-7.json"

# --- run the helper for a PR number, return its single-line .state ---
state_of() { # number
  bash "$SCRIPT_DIR/pr-status.sh" --repo test/repo "$1" | jq -r '.state'
}

check "1 open PR maps to Open"                     "$(state_of 1)" "Open"
check "2 draft PR maps to Draft"                   "$(state_of 2)" "Draft"
check "3 merged PR maps to Merged"                 "$(state_of 3)" "Merged"
check "4 draft-closed PR maps to CLOSED"           "$(state_of 4)" "CLOSED"
check "5 closed PR maps to CLOSED"                 "$(state_of 5)" "CLOSED"
check "6 queued PR maps to In Queue"               "$(state_of 6)" "In Queue"
check "7 unmergeable-queue PR maps to Queue Failed" "$(state_of 7)" "Queue Failed"

# --- helper exits 0 and emits exactly one line of output ---
out=$(bash "$SCRIPT_DIR/pr-status.sh" --repo test/repo 1); rc=$?
check "helper exits 0"            "$rc" 0
check "helper emits one line"     "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1

rm -rf "$TMPROOT"
if [[ "$FAILED" == "0" ]]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $FAILED
