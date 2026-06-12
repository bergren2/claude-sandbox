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

echo "Bringing up sandbox (first run builds the image; later runs reuse it)..."
devcontainer up --workspace-folder "$WORKSPACE"

echo "Running review inside the sandbox..."
devcontainer exec --workspace-folder "$WORKSPACE" \
  env REVIEW_OUTPUT="${REVIEW_OUTPUT:-review.md}" POST_COMMENT="${POST_COMMENT:-false}" \
  scripts/review.sh "$BASE_REF"
