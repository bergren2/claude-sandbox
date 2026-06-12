# claude-sandbox

A reusable [Dev Container](https://containers.dev/) for running **Claude Code with
`--dangerously-skip-permissions`** safely. The container is isolated and its
outbound network is locked to an allowlist, so Claude can read, build, test, and
run tools with **no permission prompts** — the blast radius is the container, not
your machine.

Built primarily for **hands-off code reviews**, but usable for any autonomous
Claude Code session.

## Why a container?

`--dangerously-skip-permissions` removes every approval prompt. That's only safe
when the thing Claude is running inside can't hurt you. This devcontainer provides
that boundary two ways:

1. **Isolation** — Claude only touches the container's copy of the repo and a
   throwaway filesystem.
2. **Network firewall** — `init-firewall.sh` drops all outbound traffic except an
   allowlist (Anthropic API, GitHub, npm, PyPI, NuGet). Even a prompt-injection
   attack can't exfiltrate to or pull from arbitrary hosts.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Linux containers)
- One of:
  - the **[Dev Containers CLI](https://github.com/devcontainers/cli)** —
    `npm install -g @devcontainers/cli` (for the terminal-only headless flow), **or**
  - [VS Code](https://code.visualstudio.com/) + the **Dev Containers** extension
    (for the interactive flow)
- Auth, one of:
  - `ANTHROPIC_API_KEY` set on the host (passed through automatically), **or**
  - run `claude` once inside the container and log in (persists in a volume)

## Use it as an interactive sandbox

1. Open this folder (or any repo that has copied `.devcontainer/` — see below) in
   VS Code.
2. **Reopen in Container** (Command Palette → *Dev Containers: Reopen in Container*).
   First build runs the firewall script; you'll see it verify the lockdown.
3. In the container terminal:
   ```bash
   claude --dangerously-skip-permissions
   ```
   Review away — no prompts. Try `/review` or just ask it to review your branch.

## Use it headless (no VS Code)

`scripts/review-host.sh` runs the whole thing from your host terminal: it brings the
container up via the Dev Containers CLI (applying the firewall), runs the review
inside it, and writes `review.md` back into your working tree.

```bash
# on the host — no VS Code, no manual "Reopen in Container"
scripts/review-host.sh                  # review HEAD vs origin/main
scripts/review-host.sh origin/develop   # different base branch
POST_COMMENT=true scripts/review-host.sh # also post to the branch's PR (needs gh auth)
```

`--dangerously-skip-permissions` only ever runs *inside* the firewalled container;
the host just orchestrates `devcontainer up` / `exec`. The first run builds the
image (slow); later runs reuse it.

Under the hood that calls `scripts/review.sh`, which does the actual one-shot review
and assumes it's already inside the container. Run it directly if you're already in a
container shell, or wire it into a git hook, a cron job, or `docker run` in CI:

```bash
# inside the container
scripts/review.sh                      # review HEAD vs origin/main
scripts/review.sh origin/develop       # different base branch
POST_COMMENT=true scripts/review.sh    # also post to the branch's PR (needs gh auth)
```

## Drop it into another repo

The whole point is reuse. To add the sandbox to one of your Python or newer-.NET
repos, copy the `.devcontainer/` folder in and layer the language toolchain on top
via [Dev Container Features](https://containers.dev/features):

```jsonc
// add to that repo's .devcontainer/devcontainer.json
"features": {
  "ghcr.io/devcontainers/features/python:1": {},
  // or:
  "ghcr.io/devcontainers/features/dotnet:2": { "version": "8.0" }
}
```

Also copy `scripts/review.sh` and `scripts/review-host.sh` if you want the headless flow.

> The older `kam` repo (ASP.NET MVC5 / MSBuild / Visual Studio targets) does **not**
> containerize cleanly on Linux — review there is better done via the GitHub Action
> or locally with an allowlist. This template targets the stacks that do.

## Adjusting the firewall

If a session needs another host (an internal package feed, a docs site, etc.), add
the domain to `ALLOWED_DOMAINS` in `.devcontainer/init-firewall.sh` and rebuild the
container. The script fails the build if the lockdown can't be verified, so a broken
allowlist surfaces immediately rather than silently leaving the box open.

## What's where

| Path | Purpose |
|------|---------|
| `.devcontainer/Dockerfile` | Base image: Node + git/gh + Claude Code + firewall tooling |
| `.devcontainer/init-firewall.sh` | Outbound allowlist (runs on every container start) |
| `.devcontainer/devcontainer.json` | Container config, caps, mounts, env passthrough |
| `scripts/review-host.sh` | Host driver: `devcontainer up` + `exec` → in-container review |
| `scripts/review.sh` | In-container branch-diff review → `review.md` (optional PR comment) |

## Caveats

- The firewall blocks general web access, so Claude's WebSearch/WebFetch won't reach
  arbitrary sites inside the container. Add domains to the allowlist if you need them.
- `--dangerously-skip-permissions` is only safe **inside** this container. Never pass
  it on your host.
