#!/usr/bin/env bash
# pr-comments.sh - Fetch PR comments and output structured JSONL.
#
# Usage: pr-comments.sh [--repo OWNER/REPO] [--resolved] PR_NUMBER
# Output: one JSON object per line (JSONL), summary object as final line

set -euo pipefail

repo=""
include_resolved=false
pr_number=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --resolved)
      include_resolved=true
      shift
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      pr_number="$1"
      shift
      ;;
  esac
done

if [[ -z "$pr_number" ]]; then
  echo "Usage: pr-comments.sh [--repo OWNER/REPO] [--resolved] PR_NUMBER" >&2
  exit 1
fi

# Resolve repo owner/name
if [[ -n "$repo" ]]; then
  gql_owner="${repo%%/*}"
  gql_name="${repo##*/}"
else
  repo_json=$(gh repo view --json owner,name)
  gql_owner=$(jq -r '.owner.login' <<< "$repo_json")
  gql_name=$(jq -r '.name' <<< "$repo_json")
  repo="${gql_owner}/${gql_name}"
fi

# --- Fetch all data ---

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# 1. GraphQL: review thread metadata (resolved, outdated, thread IDs)
GQL_QUERY='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 100) {
            nodes {
              databaseId
            }
          }
        }
      }
    }
  }
}'

gql_response=$(gh api graphql -f query="$GQL_QUERY" \
  -f owner="$gql_owner" -f name="$gql_name" -F number="$pr_number" 2>/dev/null || echo '{}')

# Build lookup: comment_database_id -> { thread_id, is_resolved, is_outdated }
thread_meta=$(jq -c '
  [(.data.repository.pullRequest.reviewThreads.nodes // [])[] |
    . as $thread |
    (.comments.nodes // [])[] |
    {
      key: (.databaseId | tostring),
      value: {
        thread_id: $thread.id,
        is_resolved: $thread.isResolved,
        is_outdated: $thread.isOutdated
      }
    }
  ] | from_entries
' <<< "$gql_response")

# 2. REST: line-specific review comments
if ! gh api --paginate "repos/${repo}/pulls/${pr_number}/comments" > "$tmp_dir/review.json" 2>/dev/null; then
  echo '[]' > "$tmp_dir/review.json"
fi
[[ -s "$tmp_dir/review.json" ]] || echo '[]' > "$tmp_dir/review.json"

# 3. REST: general PR-level comments
if ! gh api --paginate "repos/${repo}/issues/${pr_number}/comments" > "$tmp_dir/issue.json" 2>/dev/null; then
  echo '[]' > "$tmp_dir/issue.json"
fi
[[ -s "$tmp_dir/issue.json" ]] || echo '[]' > "$tmp_dir/issue.json"

# --- Process and output JSONL ---

JQ_PROGRAM='
def detect_severity:
  if test("(?im)^\\s*(?:\\*\\*)?\\s*issue\\s*\\(\\s*blocking\\s*\\)\\s*(?:\\*\\*)?\\s*:") then "blocking"
  elif test("(?im)^\\s*(?:\\*\\*)?\\s*issue\\s*\\(\\s*non-blocking\\s*\\)\\s*(?:\\*\\*)?\\s*:") then "non-blocking"
  elif test("(?im)^\\s*(?:\\*\\*)?\\s*suggestion\\s*(?:\\*\\*)?\\s*:") then "suggestion"
  elif test("(?im)^\\s*(?:\\*\\*)?\\s*nitpick\\s*(?:\\*\\*)?\\s*:") then "suggestion"
  elif test("(?im)^\\s*(?:\\*\\*)?\\s*question\\s*(?:\\*\\*)?\\s*:") then "question"
  elif test("_⚠️ Potential issue_") then "blocking"
  elif test("_🟠 Major_") then "blocking"
  elif test("_🟡 Minor_") then "non-blocking"
  else "unknown"
  end;

def sanitize_body:
  gsub("<!--[\\s\\S]*?-->"; "") |
  gsub("<details>(?:(?!</details>)[\\s\\S])*(?:Committable suggestion|Prompt for AI Agents|internal state)(?:(?!</details>)[\\s\\S])*</details>"; "") |
  gsub("\\n{3,}"; "\\n\\n") |
  gsub("^[\\s\\n]+"; "") |
  gsub("[\\s\\n]+$"; "");

# Process review comments
[($review[0] // [])[] | {
  id: .id,
  user: .user.login,
  type: "review_comment",
  severity: (.body | detect_severity),
  path: .path,
  line: (.line // .original_line // null),
  url: .html_url,
  body: (.body | sanitize_body),
  created_at: .created_at,
  outdated: ($thread_meta[(.id | tostring)].is_outdated // false),
  resolved: ($thread_meta[(.id | tostring)].is_resolved // false),
  thread_id: ($thread_meta[(.id | tostring)].thread_id // null),
  in_reply_to: (.in_reply_to_id // null)
}] as $rev_comments |

# Process issue comments
[($issue[0] // [])[] | {
  id: .id,
  user: .user.login,
  type: "issue_comment",
  severity: (.body | detect_severity),
  path: null,
  line: null,
  url: .html_url,
  body: (.body | sanitize_body),
  created_at: .created_at,
  outdated: false,
  resolved: false,
  thread_id: null,
  in_reply_to: null
}] as $iss_comments |

# Combine, filter resolved, sort
($rev_comments + $iss_comments) |
[.[] | select($include_resolved or (.resolved | not))] |
sort_by(.created_at) |
. as $all |

# Output each comment
$all[],

# Output summary as final line
{
  summary: true,
  total: ($all | length),
  by_user: (
    [$all[].user] | group_by(.) |
    map({key: .[0], value: length}) |
    from_entries
  ),
  by_severity: (
    [$all[].severity] | group_by(.) |
    map({key: .[0], value: length}) |
    from_entries
  ),
  outdated: ([$all[] | select(.outdated)] | length),
  resolved: ([$all[] | select(.resolved)] | length)
}
'

jq -n -c \
  --slurpfile review "$tmp_dir/review.json" \
  --slurpfile issue "$tmp_dir/issue.json" \
  --argjson thread_meta "$thread_meta" \
  --argjson include_resolved "$include_resolved" \
  "$JQ_PROGRAM" |
# Strip lone UTF-16 surrogates (U+D800..U+DFFF) from string fields. These are
# valid in JSON syntax but invalid as Unicode and cause the Anthropic API to
# reject the entire conversation ("no low surrogate in string"). Also normalises
# any malformed UTF-8 bytes from upstream (GitHub comment bodies) to U+FFFD.
python3 -c '
import sys, json, re

_SURROGATE = re.compile(r"[\ud800-\udfff]")

def scrub(o):
    if isinstance(o, str):
        return _SURROGATE.sub("�", o)
    if isinstance(o, dict):
        return {k: scrub(v) for k, v in o.items()}
    if isinstance(o, list):
        return [scrub(x) for x in o]
    return o

data = sys.stdin.buffer.read().decode("utf-8", errors="replace")
for line in data.split("\n"):
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    print(json.dumps(scrub(obj), ensure_ascii=False))
'
