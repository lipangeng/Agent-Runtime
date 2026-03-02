FROM docker.rarely.pro/library/debian:latest

RUN set -eux ;\
    apt-get update ;\
    \
    apt-get install -y \
        bash zsh fish openssl sudo \
        htop tcpdump busybox tini libncurses6 strace lsof coreutils tmux sysstat\
        curl wget vim bind9-dnsutils nmap iproute2 dnsutils 7zip\
        psmisc tree jq cmake\
      	unzip zip bash-completion \
        fontconfig fonts-dejavu zlib1g \
        gnupg ca-certificates p11-kit tzdata \
    	nodejs npm python3 \
    	git gh pandoc \
    	;\
    \
    apt-get clean ;\
    rm -rf /var/lib/apt/lists/* ;\
    rm -rf /tmp/*

RUN set -eux ;\
    apt-get update ;\
    \
    npm install -g playwright@latest @playwright/cli@latest ;\
    playwright-cli install ;\
    playwright install-deps chrome ;\
    \
    npm cache clean --force ;\
    rm -rf ~/.npm/_npx ;\
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
    chown agent:agent /workspace

USER agent

WORKDIR /workspace

ENTRYPOINT ["/sbin/tini","--"]

CMD ["bash"]
