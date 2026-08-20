#!/bin/bash
# Refresh <worktree>/.local/.pr-status.json and <worktree>/.local/PR-STATUS.md
# per the PR-status cache protocol (docs/protocols/pr-status-cache.md).
#
# Usage: pr-status-refresh.sh <worktree-dir> [ttl-seconds]   (default TTL 60)
#
# Shared engine behind the Stop hook (turn-end refresh, short TTL); other
# callers may invoke it with a longer TTL against the same cache.
#
# - TTL guard: skip when the JSON cache is younger than ttl-seconds.
# - mkdir lock: concurrent callers collapse to one refresh. Locks older than
#   120s are treated as crashed refreshers and broken.
# - Coordination worktree (non-empty .local/.orchestrator = active effort):
#   scrapes PR URLs from the worktree's .local planning docs — `**PR:**`
#   fields in PLAN.md / plans/*.md first, then any PR URL in TODO.md, PLAN.md,
#   WORKGRAPH.md — and writes a `prs` array.
# - Other worktrees (including an empty .orchestrator, which is topology only):
#   resolve the branch's own PR via gh. When the branch has no PR at all,
#   fall back to the same doc scrape: coordination worktrees shepherd PRs
#   that live on delegated branches, and their .local docs carry the URLs
#   even when git doesn't. A doc that references an unrelated PR can badge
#   it as a false positive; accepted tradeoff for a glanceable hint.
# - Preserve-on-failure: gh/network failures exit without writing, so a
#   background refresh never blanks a previously good cache.
# - Silent-exits on any failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wt="${1:-}"
ttl="${2:-60}"
[[ "$ttl" =~ ^[0-9]+$ ]] || ttl=60

[[ -n "$wt" && -d "$wt" ]] || exit 0

# Normalise to the worktree root so subdir callers (a session whose cwd sits
# below the root) and root callers agree on where .local lives.
toplevel=$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)
[[ -n "$toplevel" ]] && wt="$toplevel"
[[ -d "$wt/.local" ]] || exit 0

json_file="$wt/.local/.pr-status.json"
md_file="$wt/.local/PR-STATUS.md"

# Epoch mtime, platform-aware and self-contained so the engine stays a single
# vendorable file: BSD stat takes -f %m, GNU stat takes -c %Y, and mixing the
# two behind `||` leaks GNU's multi-line filesystem dump into the capture.
mtime_epoch() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f %m "$1" 2>/dev/null || echo 0
    else
        stat -c %Y "$1" 2>/dev/null || echo 0
    fi
}

# TTL guard: skip if the cache is fresh enough for this caller.
if [[ -f "$json_file" ]] && (( $(date +%s) - $(mtime_epoch "$json_file") < ttl )); then
    exit 0
fi

helper="$SCRIPT_DIR/pr-status.sh"
[[ -f "$helper" ]] || exit 0

# One refresh per worktree at a time; break locks older than 120s. The lock
# records its owner's PID: a peer can break a stale lock and re-create it, so
# the EXIT trap must release only a lock this process still owns.
lock_dir="$wt/.local/.pr-status-refresh.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
    (( $(date +%s) - $(mtime_epoch "$lock_dir") > 120 )) || exit 0
    rm -rf "$lock_dir" 2>/dev/null
    mkdir "$lock_dir" 2>/dev/null || exit 0
fi
printf '%s' "$$" > "$lock_dir/pid" 2>/dev/null
trap '[[ "$(cat "$lock_dir/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$lock_dir" 2>/dev/null' EXIT

fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Scrape PR URLs from the .local docs. Prefer structured `**PR:**` fields in
# the plan documents when present (narrowest scope, avoids referenced-but-
# unrelated PRs), then ungrep TODO.md, then PLAN.md, then WORKGRAPH.md.
scrape_doc_urls() {
    local urls=""
    urls=$(cat "$wt/.local/PLAN.md" "$wt/.local/plans/"*.md 2>/dev/null \
        | grep -E '\*\*PR:\*\*' \
        | grep -oE 'https://github\.com/[^/ )]+/[^/ )]+/pull/[0-9]+' \
        | sort -u)
    local doc
    for doc in TODO.md PLAN.md WORKGRAPH.md; do
        [[ -z "$urls" && -f "$wt/.local/$doc" ]] || continue
        urls=$(grep -oE 'https://github\.com/[^/ )]+/[^/ )]+/pull/[0-9]+' "$wt/.local/$doc" 2>/dev/null | sort -u)
    done
    printf '%s' "$urls"
}

# Fetch each URL in parallel via the helper; emit a JSON array on stdout.
# Per-URL failures are swallowed so one bad PR (deleted, permissioned out)
# does not blank the whole list; an all-fail run emits [].
# Zero-padded index names + sorted glob expansion keep the array in URL order
# across runs (fetches complete in network-timing order, and directory
# enumeration order is unspecified), so multi-PR consumers never see entries
# swap positions between refreshes. Failed fetches leave empty files, which
# add nothing to the concatenated stream.
fetch_prs_array() {
    local urls="$1" tmp_dir i url arr
    tmp_dir=$(mktemp -d 2>/dev/null) || { printf '[]'; return; }
    i=0
    for url in $urls; do
        (cd "$wt" && bash "$helper" "$url" 2>/dev/null) > "$tmp_dir/$(printf '%04d' "$i").json" &
        i=$((i + 1))
    done
    wait
    arr=$(cat "$tmp_dir"/*.json 2>/dev/null | jq -s '.' 2>/dev/null)
    rm -rf "$tmp_dir"
    if [[ -z "$arr" || "$arr" == "null" ]]; then
        arr='[]'
    fi
    printf '%s' "$arr"
}

# Write the protocol's `.pr-status.json` shape: `prs` always carries 0, 1, or
# N entries; the deprecated `pr` key mirrors the single entry when there is
# exactly one PR, else null (retained for readers not yet on `prs[]`). Every
# JSON write in this script routes through here. Args: branch, prs_array.
write_prs_shape() {
    local branch="$1" prs_array="$2"
    local tmp_json
    tmp_json=$(mktemp 2>/dev/null) || exit 0
    jq -n --arg branch "${branch:-}" --arg fetched_at "$fetched_at" --argjson prs "$prs_array" \
        '{branch: $branch, fetched_at: $fetched_at,
          pr: (if ($prs | length) == 1 then $prs[0] else null end),
          prs: $prs}' > "$tmp_json" 2>/dev/null || { rm -f "$tmp_json"; exit 0; }
    mv "$tmp_json" "$json_file" 2>/dev/null
}

# Write the compact `PR-STATUS.md` bullet list rendered from a `prs` array.
# Paths with a bespoke human layout (the single branch-PR path) write their own
# Markdown instead. Args: branch, prs_array, md_title, md_lede.
write_prs_md() {
    local branch="$1" prs_array="$2" md_title="$3" md_lede="$4"
    local tmp_md
    tmp_md=$(mktemp 2>/dev/null) || exit 0
    {
        printf '# %s\n\n' "$md_title"
        # shellcheck disable=SC2016  # literal markdown backticks, not a command substitution
        printf '**Branch:** `%s`  \n' "${branch:-(none)}"
        printf '**Fetched:** %s\n\n' "$fetched_at"
        printf '%s\n\n' "$md_lede"
        if [[ "$(jq 'length' <<< "$prs_array" 2>/dev/null)" == "0" ]]; then
            printf 'No PRs to display.\n'
        else
            jq -r '.[] | "- **PR #\(.number)** — \(.title)\n  - State: \(.state) | Reviews: \(.reviews) | CI: \(.ci) | Comments: \(.comments)\n  - \(.url)"' <<< "$prs_array"
        fi
    } > "$tmp_md"
    mv "$tmp_md" "$md_file" 2>/dev/null
}

# ----- Coordination path ----------------------------------------------------
# A non-empty .local/.orchestrator marks an active coordination effort whose
# branch typically has no PR of its own; the work lives on PRs scattered
# across delegated branches. Scrape the docs and fetch each.
if [[ -s "$wt/.local/.orchestrator" ]]; then
    branch=$(git -C "$wt" branch --show-current 2>/dev/null)
    urls=$(scrape_doc_urls)

    if [[ -z "$urls" ]]; then
        # Coordination worktree with no PRs yet — emit empty array.
        write_prs_shape "$branch" '[]'
        write_prs_md "$branch" '[]' "PR Status" \
            "Coordination worktree; no PR URLs found in the .local planning docs."
        exit 0
    fi

    prs_array=$(fetch_prs_array "$urls")
    pr_count=$(jq 'length' <<< "$prs_array" 2>/dev/null)
    if [[ "${pr_count:-0}" -eq 0 ]]; then
        # URLs exist but every fetch failed (network, auth) — keep the old cache.
        exit 0
    fi

    write_prs_shape "$branch" "$prs_array"
    write_prs_md "$branch" "$prs_array" "PR Status (Coordination)" \
        "## Shepherded PRs ($pr_count)"
    exit 0
fi

# ----- Standalone path -------------------------------------------------------
# Resolve branch; bail on detached HEAD or default branches.
branch=$(git -C "$wt" branch --show-current 2>/dev/null)
[[ -n "$branch" ]] || exit 0
case "$branch" in master|main|HEAD) exit 0 ;; esac

# Look up the branch's own PR (open or merged, most recent first). A gh
# failure aborts the refresh so a network blip can't blank a good cache;
# only a successful empty result means "this branch has no PR".
pr_number=$(cd "$wt" && gh pr list --head "$branch" --state all --json number --jq '.[0].number // empty' 2>/dev/null) || exit 0

if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
    pr_json=$(cd "$wt" && bash "$helper" "$pr_number" 2>/dev/null)
    [[ -n "$pr_json" ]] || exit 0

    # Unify to the `prs[]` shape: a lone branch PR is a single-entry array, and
    # write_prs_shape mirrors it into the deprecated `pr` key. PR-STATUS.md
    # keeps its detailed single-PR layout below rather than the compact list.
    prs_array=$(jq -n --argjson pr "$pr_json" '[$pr]' 2>/dev/null) || exit 0
    write_prs_shape "$branch" "$prs_array"

    tmp_md=$(mktemp 2>/dev/null) || exit 0

    title=$(jq -r '.title // ""' <<< "$pr_json")
    url=$(jq -r '.url // ""' <<< "$pr_json")
    state=$(jq -r '.state // ""' <<< "$pr_json")
    size=$(jq -r '.size // ""' <<< "$pr_json")
    reviews=$(jq -r '.reviews // ""' <<< "$pr_json")
    ci=$(jq -r '.ci // ""' <<< "$pr_json")
    requested=$(jq -r '.requested // ""' <<< "$pr_json")
    comments=$(jq -r '.comments // 0' <<< "$pr_json")
    {
        printf '# PR Status\n\n'
        # shellcheck disable=SC2016  # literal markdown backticks, not a command substitution
        printf '**Branch:** `%s`  \n' "$branch"
        printf '**Fetched:** %s\n\n' "$fetched_at"
        printf '## PR #%s — %s\n\n' "$pr_number" "$title"
        printf -- '- **URL:** %s\n' "$url"
        printf -- '- **State:** %s\n' "$state"
        printf -- '- **Size:** %s\n' "$size"
        printf -- '- **Reviews:** %s\n' "$reviews"
        printf -- '- **CI:** %s\n' "$ci"
        printf -- '- **Requested:** %s\n' "$requested"
        printf -- '- **Unreplied comments:** %s\n' "$comments"
    } > "$tmp_md"

    mv "$tmp_md" "$md_file" 2>/dev/null
    exit 0
fi

# The branch has no PR of its own. Coordination-shaped worktrees (including a
# handover-scaffolded one whose .orchestrator marker is still empty — topology
# only, no active effort) shepherd PRs living on delegated branches; their
# docs carry the URLs. Fall back to the same scrape the coordination path uses.
urls=$(scrape_doc_urls)

if [[ -n "$urls" ]]; then
    prs_array=$(fetch_prs_array "$urls")
    pr_count=$(jq 'length' <<< "$prs_array" 2>/dev/null)
    if [[ "${pr_count:-0}" -eq 0 ]]; then
        # URLs exist but every fetch failed — keep the old cache.
        exit 0
    fi
    write_prs_shape "$branch" "$prs_array"
    write_prs_md "$branch" "$prs_array" "PR Status" \
        "No PR found for branch \`$branch\`. Showing $pr_count PR(s) referenced in \`.local/\` docs."
    exit 0
fi

# No PR, no referenced URLs — record the genuine absence as an empty `prs[]`.
write_prs_shape "$branch" '[]'
write_prs_md "$branch" '[]' "PR Status" "No PR found for branch \`$branch\`."

exit 0
