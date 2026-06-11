#!/usr/bin/env bash
# Headless Claude Code review of the current branch's diff.
#
# Intended to run INSIDE the sandboxed devcontainer, where
# --dangerously-skip-permissions is safe (network is firewalled, the
# container is disposable). Do NOT run this on your host with that flag.
#
# Usage:
#   scripts/review.sh [base-ref]              # review HEAD vs base-ref (default origin/main)
#   POST_COMMENT=true scripts/review.sh       # also post findings to the branch's PR via gh
#
# Env:
#   REVIEW_OUTPUT   output file (default: review.md)
#   POST_COMMENT    "true" to post the review as a PR comment (needs gh auth / GH_TOKEN)
set -euo pipefail

BASE_REF="${1:-origin/main}"
OUTPUT="${REVIEW_OUTPUT:-review.md}"
POST_COMMENT="${POST_COMMENT:-false}"

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' not found — are you inside the devcontainer?" >&2
  exit 1
fi

git fetch --quiet origin || true

if git diff --quiet "${BASE_REF}"...HEAD 2>/dev/null; then
  echo "No changes against ${BASE_REF}; nothing to review."
  exit 0
fi

echo "Reviewing changes against ${BASE_REF}..."

PROMPT="Review the changes on the current git branch compared to ${BASE_REF}. \
Run 'git diff ${BASE_REF}...HEAD' to see them, and read related files in the \
repo to judge correctness. Report findings for correctness bugs, security \
issues, and clear simplification/reuse opportunities. For each finding give: \
file:line, severity (blocker/high/medium/low/nit), what's wrong, and a concrete \
fix. Group by severity, most severe first. Be concise. If the diff is clean, \
say so plainly. Output GitHub-flavored markdown suitable for a PR comment."

claude -p "$PROMPT" --dangerously-skip-permissions | tee "$OUTPUT"

echo ""
echo "Review written to ${OUTPUT}"

if [ "$POST_COMMENT" = "true" ]; then
  if command -v gh >/dev/null 2>&1; then
    echo "Posting review as a PR comment..."
    gh pr comment --body-file "$OUTPUT" || echo "WARN: gh pr comment failed (no open PR for this branch?)" >&2
  else
    echo "WARN: gh not available; skipping PR comment." >&2
  fi
fi
