FROM docker.rarely.pro/library/debian:latest

RUN set -eux ;\
    apt-get update -y;\
    \
    apt-get install -y \
        bash zsh fish openssl sudo \
        htop tcpdump busybox tini libncurses6 strace lsof coreutils tmux sysstat\
        curl wget vim bind9-dnsutils nmap iproute2 dnsutils 7zip\
        psmisc tree jq cmake\
      	unzip zip bash-completion \
        fontconfig fonts-dejavu zlib1g \
        gnupg ca-certificates p11-kit tzdata \
    	python3 python3-venv python3-pip \
    	git gh pandoc \
    	;\
    \
    install -dm 755 /etc/apt/keyrings ;\
    curl -fSs https://mise.jdx.dev/gpg-key.pub | sudo tee /etc/apt/keyrings/mise-archive-keyring.asc 1> /dev/null ;\
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.asc] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list ;\
    apt update -y ;\
    apt install -y mise ;\
    mkdir -p /opt/mise/{config,data,cache} ;\
    \
    apt-get clean ;\
    rm -rf /var/lib/apt/lists/* ;\
    rm -rf /tmp/*

ENV MISE_ROOT=/opt/mise \
	XDG_CACHE_HOME=/opt/mise/cache \
	XDG_DATA_HOME=/opt/mise/data \
	XDG_CONFIG_HOME=/opt/mise/config \
	PATH=/opt/mise/data/shims:$PATH

RUN set -eux ;\
    apt-get update -y;\
  	\
    mise use -g node@lts ;\
    \
    mise exec -- npm install -g playwright@latest @playwright/cli@latest ;\
    mise exec -- playwright install --with-deps chrome ;\
    \
    mise exec -- npm cache clean --force || true ;\
    \
    mise reshim ;\
    \
    apt-get clean ;\
    rm -rf /var/lib/apt/lists/* ;\
    rm -rf /tmp/*

RUN set -eux ;\
    \
    groupadd -g 1024 agent ;\
    useradd -u 1024 -g agent -m agent -s /bin/bash ;\
    echo "agent ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent ;\
    \
    mkdir /workspace ;\
    chown agent:agent /workspace /opt/mise

USER agent

WORKDIR /workspace