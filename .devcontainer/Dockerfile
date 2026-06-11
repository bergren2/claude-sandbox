FROM node:20-bookworm

ARG TZ
ENV TZ="$TZ"

# Base tooling used by Claude Code and the firewall init script.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
  && apt-get -y install --no-install-recommends \
    less \
    git \
    procps \
    sudo \
    fzf \
    zsh \
    unzip \
    gnupg2 \
    gh \
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    jq \
    ca-certificates \
    curl \
  && rm -rf /var/lib/apt/lists/*

ARG USERNAME=node

# Persist shell history across rebuilds (volume-mounted in devcontainer.json).
RUN mkdir -p /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME:$USERNAME /commandhistory
ENV HISTFILE=/commandhistory/.bash_history

# Passwordless sudo ONLY for the firewall init script — nothing else.
RUN echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/init-firewall \
  && chmod 0440 /etc/sudoers.d/init-firewall

# Install Claude Code globally.
RUN npm install -g @anthropic-ai/claude-code

# Firewall init script (run from postCreateCommand via sudo).
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

WORKDIR /workspace
USER node
ENV SHELL=/bin/zsh
