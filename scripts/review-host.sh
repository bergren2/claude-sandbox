#!/usr/bin/env bash
# Host-side driver for a sandboxed review — no VS Code required.
#
# Brings the devcontainer up headlessly via the Dev Containers CLI (which runs
# the firewall on start), then execs the in-container review. The review writes
# review.md into the mounted repo, so it lands back in your working tree.
#
# --dangerously-skip-permissions only ever runs INSIDE the firewalled container
# (via `devcontainer exec` → scripts/review.sh). It is never run on the host.
#
# Usage:
#   scripts/review-host.sh [base-ref]         # review HEAD vs base-ref (default origin/main)
#
# Env (forwarded into the container):
#   REVIEW_OUTPUT   output file (default: review.md)
#   POST_COMMENT    "true" to post findings to the branch's PR via gh
#
# Host prereqs:
#   - Docker running (Docker Desktop)
#   - Dev Containers CLI:  npm install -g @devcontainers/cli
#   - ANTHROPIC_API_KEY set on the host (forwarded via devcontainer.json), or a
#     prior `claude` login persisted in the claude-sandbox-config volume.
set -euo pipefail

BASE_REF="${1:-origin/main}"
WORKSPACE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found on host. Install Docker Desktop and start it." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon not reachable — is Docker Desktop running?" >&2
  exit 1
fi
if ! command -v devcontainer >/dev/null 2>&1; then
  echo "ERROR: Dev Containers CLI not found. Install it with:" >&2
  echo "         npm install -g @devcontainers/cli" >&2
  exit 1
fi

# The in-container `claude -p` needs non-interactive auth. An interactive login
# inside the container does NOT persist (~/.claude.json lives at HOME, outside
# the mounted volume), so require a token in the host env and fail fast — better
# than letting claude loop on "configuration file not found".
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${ANTHROPIC_AUTH_TOKEN:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "ERROR: no Claude auth in the environment. Set one of these on the host" >&2
  echo "       (devcontainer.json forwards them into the container):" >&2
  echo "         export ANTHROPIC_API_KEY=...           # API billing" >&2
  echo "         export CLAUDE_CODE_OAUTH_TOKEN=...      # subscription; from 'claude setup-token'" >&2
  exit 1
fi

# Fetch the base ref on the HOST, which has GitHub credentials — the firewalled
# container can't authenticate to GitHub. This keeps the in-container diff against
# a fresh base; the container's own fetch is left as a no-auth best-effort.
echo "Fetching latest from origin (on host)..."
git -C "$WORKSPACE" fetch --quiet origin 2>/dev/null \
  || echo "WARN: host fetch failed; the diff will use existing local refs." >&2

# Bring the container up with auth tokens stripped from the environment, so they
# are NOT baked into the `docker run` command that the CLI echoes to its log.
# Auth is injected only at exec time via --remote-env, which the CLI does not print.
echo "Bringing up sandbox (first run builds the image; later runs reuse it)..."
(
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN
  devcontainer up --workspace-folder "$WORKSPACE"
)

# Forward whichever auth token is set, plus the review options, via --remote-env.
exec_env=()
for var in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
  [ -n "${!var:-}" ] && exec_env+=( --remote-env "$var=${!var}" )
done

echo "Running review inside the sandbox..."
devcontainer exec --workspace-folder "$WORKSPACE" \
  "${exec_env[@]}" \
  --remote-env "REVIEW_OUTPUT=${REVIEW_OUTPUT:-review.md}" \
  --remote-env "POST_COMMENT=${POST_COMMENT:-false}" \
  scripts/review.sh "$BASE_REF"
