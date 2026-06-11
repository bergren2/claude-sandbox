#!/bin/bash
# Locks the container down to an outbound allowlist. Everything not explicitly
# allowed is dropped, so even with --dangerously-skip-permissions an agent
# cannot exfiltrate to or pull from arbitrary hosts.
#
# Add domains your stack needs (package registries, internal feeds) to the
# ALLOWED_DOMAINS list below, then rebuild the container.
set -euo pipefail
IFS=$'\n\t'

ALLOWED_DOMAINS=(
  registry.npmjs.org      # npm (Claude Code itself)
  api.anthropic.com       # Claude API
  sentry.io               # Claude Code telemetry
  statsig.anthropic.com
  statsig.com
  pypi.org                # Python packages
  files.pythonhosted.org
  api.nuget.org           # .NET packages
  dist.nuget.org
)

# Flush existing rules and ipsets.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# DNS and loopback must work before we lock things down.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT

ipset create allowed-domains hash:net

# GitHub publishes its IP ranges — add web/api/git so gh and git over HTTPS work.
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
  echo "ERROR: failed to fetch GitHub IP ranges" >&2
  exit 1
fi
while read -r cidr; do
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || continue
  ipset add allowed-domains "$cidr" 2>/dev/null || true
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and allow each domain in the list.
for domain in "${ALLOWED_DOMAINS[@]}"; do
  echo "Resolving $domain..."
  ips=$(dig +short A "$domain" || true)
  if [ -z "$ips" ]; then
    echo "WARNING: could not resolve $domain; skipping" >&2
    continue
  fi
  while read -r ip; do
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
    ipset add allowed-domains "$ip" 2>/dev/null || true
  done < <(echo "$ips")
done

# Allow the host/docker network (so VS Code can talk to the container).
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -n "$HOST_IP" ]; then
  HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
  iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
  iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Default-deny, then allow established connections and the allowlist.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Verify: arbitrary internet blocked, allowlist reachable.
echo "Verifying firewall..."
if curl --connect-timeout 5 -s https://example.com >/dev/null 2>&1; then
  echo "ERROR: firewall failed — example.com is reachable but should be blocked" >&2
  exit 1
fi
if ! curl --connect-timeout 5 -s https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: firewall failed — api.github.com is NOT reachable but should be" >&2
  exit 1
fi
echo "Firewall configured: arbitrary internet blocked, allowlist reachable."
