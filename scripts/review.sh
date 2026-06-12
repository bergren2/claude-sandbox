#!/usr/bin/env bash
# Headless Claude Code review of the current branch's diff.
#
# Intended to run INSIDE the sandboxed devcontainer, where
# --dangerously-skip-permissions is safe (network is firewalled, the
# container is disposable). Do NOT run this on your host with that flag.
#
# Usage:
#   scripts/review.sh [base-ref]              # review HEAD vs base-ref (default origin/main)
#
# Writes the review to REVIEW_OUTPUT and does NOT post it — the firewalled
# sandbox holds no GitHub credentials by design. Post from the host instead: the
# review-host.sh driver does this automatically when POST_COMMENT=true, or run
# `gh pr comment --body-file review.md` yourself from the host.
#
# Env:
#   REVIEW_OUTPUT   output file (default: review.md)
set -euo pipefail

BASE_REF="${1:-origin/main}"
OUTPUT="${REVIEW_OUTPUT:-review.md}"

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' not found — are you inside the devcontainer?" >&2
  exit 1
fi

# Best-effort: the host driver (review-host.sh) already fetches the base ref with
# credentials before exec, so origin refs are present in the mounted repo. GitHub
# is firewalled off inside the container, so this fetch is expected to fail here —
# silence it.
git fetch --quiet origin 2>/dev/null || true

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
echo "(Posting is the host's job — see review-host.sh / POST_COMMENT.)"
