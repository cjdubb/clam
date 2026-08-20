#!/usr/bin/env bash
# pr-status.sh - Fetch live PR status from GitHub and output structured JSON.
#
# Usage: pr-status.sh [--repo OWNER/REPO] PR_URL_OR_NUMBER [PR_URL_OR_NUMBER...]
# Output: one JSON object per line with fields: number, title, url, size, state, reviews, requested, ci, mergeable, mergeStateStatus, comments, tier, tier_label

set -euo pipefail

repo=""
prs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    *)
      prs+=("$1")
      shift
      ;;
  esac
done

if [[ ${#prs[@]} -eq 0 ]]; then
  echo "Usage: pr-status.sh [--repo OWNER/REPO] PR_URL_OR_NUMBER [...]" >&2
  exit 1
fi

repo_args=()
if [[ -n "$repo" ]]; then
  repo_args=(--repo "$repo")
  gql_owner="${repo%%/*}"
  gql_name="${repo##*/}"
else
  repo_json=$(gh repo view --json owner,name)
  gql_owner=$(jq -r '.owner.login' <<< "$repo_json")
  gql_name=$(jq -r '.name' <<< "$repo_json")
fi

JQ_EXPR='
def addcommas:
  def grp: if length <= 3 then [.] else (.[:-3] | grp) + [.[-3:]] end;
  tostring | grp | join(",");

{
  number: .number,
  title: .title,
  url: .url,
  size: ("+" + ((.additions // 0) | addcommas) + " -" + ((.deletions // 0) | addcommas)),
  state: (
    if .state == "MERGED" then "Merged"
    elif .state == "CLOSED" then "CLOSED"
    elif .isDraft then "Draft"
    elif .state == "OPEN" then
      if (.mergeQueueEntry // null) == null then "Open"
      elif (.mergeQueueEntry.state | IN("QUEUED","AWAITING_CHECKS","MERGEABLE","LOCKED")) then "In Queue"
      elif .mergeQueueEntry.state == "UNMERGEABLE" then "Queue Failed"
      else "Open"
      end
    else .state
    end),
  queuePosition: (.mergeQueueEntry.position // null),
  queueState: (.mergeQueueEntry.state // null),
  reviews: (
    if .reviewDecision == "APPROVED" then "Approved"
    elif .reviewDecision == "CHANGES_REQUESTED" then "Changes Requested"
    elif .reviewDecision == "REVIEW_REQUIRED" then
      if ([.reviews[] | select(.state == "APPROVED")] | length) > 0 then "Approved (stale)"
      elif (.reviewRequests | length) > 0 then "Pending"
      else "Not Requested"
      end
    else
      ([ .reviews[] | {author: .author.login, state: .state} ] | group_by(.author) | map(sort_by(.submittedAt) | last) |
        if length == 0 then "Not Requested"
        elif any(.state == "APPROVED") then "Approved"
        elif any(.state == "CHANGES_REQUESTED") then "Changes Requested"
        else "Commented"
        end)
    end),
  requested: ([.reviewRequests[] | (.login // .name)] | if length == 0 then "-" else join(", ") end),
  ci: (
    [.statusCheckRollup[] |
      if .__typename == "CheckRun" then
        if .status == "COMPLETED" then
          if (.conclusion | IN("SUCCESS","NEUTRAL","SKIPPED")) then "pass"
          else "fail"
          end
        else "running"
        end
      else
        if .state == "SUCCESS" then "pass"
        elif .state == "PENDING" then "running"
        else "fail"
        end
      end
    ] |
    if length == 0 then "N/A"
    elif any(. == "running") then "Running"
    elif any(. == "fail") then "Fail"
    else "Pass"
    end),
  mergeable: (.mergeable // "UNKNOWN"),
  mergeStateStatus: (.mergeStateStatus // "UNKNOWN")
} |
. + (
  if .state == "Merged" then {tier: 5, tier_label: "Merged"}
  elif .state == "In Queue" then {tier: 4.5, tier_label: "In queue"}
  elif .state == "Queue Failed" then {tier: 1, tier_label: "Queue failed"}
  elif .state == "Open" and .reviews == "Approved" and .ci == "Pass" and .mergeable != "CONFLICTING" then {tier: 4, tier_label: "Ready to enqueue"}
  elif .state == "Open" and (.reviews == "Approved" or .reviews == "Approved (stale)") then {tier: 3, tier_label: "Approved (caveats)"}
  elif .state == "Open" and .reviews == "Pending" and .ci != "Fail" then {tier: 2, tier_label: "Awaiting review"}
  else {tier: 1, tier_label: "Action required"}
  end
)'

# shellcheck disable=SC2016  # GraphQL variables ($owner, $name, $number) must stay literal
GQL_QUERY='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      mergeQueueEntry {
        position
        state
        enqueuedAt
        estimatedTimeToMerge
      }
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(last: 1) {
            nodes {
              author {
                login
              }
            }
          }
        }
      }
    }
  }
}'

for pr in "${prs[@]}"; do
  raw_json=$(gh pr view "$pr" "${repo_args[@]}" \
    --json state,isDraft,reviewDecision,reviewRequests,reviews,statusCheckRollup,title,number,url,author,additions,deletions,mergeable,mergeStateStatus)

  pr_number=$(jq -r '.number' <<< "$raw_json")
  pr_author=$(jq -r '.author.login // ""' <<< "$raw_json")

  # gh pr view --json does not expose mergeQueueEntry, so fetch queue state +
  # review threads in a single GraphQL call. Tolerate failure: if the call
  # errors or the field does not exist, mergeQueueEntry stays null and the PR
  # falls back to standard tier logic.
  queue_entry='null'
  comments_count=0
  if gql_response=$(gh api graphql -f query="$GQL_QUERY" \
    -f owner="$gql_owner" -f name="$gql_name" -F number="$pr_number" 2>/dev/null); then
    queue_entry=$(jq -c '.data.repository.pullRequest.mergeQueueEntry // null' <<< "$gql_response")
    comments_count=$(jq --arg author "$pr_author" '
      [(.data.repository.pullRequest.reviewThreads.nodes // [])[] |
        select(.isResolved == false) |
        .comments.nodes[0] |
        select(.author != null) |
        select(.author.login != $author)
      ] | length
    ' <<< "$gql_response")
  fi
  comments_count=${comments_count:-0}

  enriched_json=$(jq --argjson q "$queue_entry" '. + {mergeQueueEntry: $q}' <<< "$raw_json")
  base_json=$(jq -c "$JQ_EXPR" <<< "$enriched_json")

  jq -c --argjson comments "${comments_count}" '. + {comments: $comments}' <<< "$base_json"
done
