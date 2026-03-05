# Agent Runtime

A general-purpose base runtime image for agent toolchains.

This project is not tied to one product. It provides a consistent, operable, and extensible container runtime for agent software such as `Codex`, `OpenCode`, and `OpenClaw`, while keeping runtime isolation at the container orchestration layer.

Language versions:

- English (default): `README.md`
- 简体中文: `README.zh-CN.md`

## Design Goals

- Provide an out-of-the-box runtime to reduce duplicated environment setup per agent.
- Include practical diagnostics and ops tooling for in-container troubleshooting.
- Support multiple agents on one base image with isolated per-agent state mounts.
- Keep the image generic; networking, security, and persistence policies are defined by deployment (Docker/Compose/Kubernetes).

## What the Image Includes

Base image: `debian:latest`

Key toolsets (subset):

- Shell and core tools: `bash`, `zsh`, `fish`, `sudo`, `tmux`, `coreutils`
- Diagnostics/network: `tcpdump`, `strace`, `lsof`, `nmap`, `iproute2`, `dnsutils`
- Dev tools: `git`, `gh`, `python3`, `pip`, `cmake`, `jq`
- Node runtime: installed via `mise` (`Node LTS`)
- Browser automation: `playwright` + `chrome`

Default user: `agent` (`uid/gid: 1024`)  
Default working directory: `/workspace`

## Scope Boundary

This repository maintains the base image only. It does not enforce one production topology.

Examples of deployment-side decisions:

- whether to use proxy/tunnel networking
- whether to use `network_mode: service:*`
- whether to enable `seccomp=unconfined` / `apparmor=unconfined`
- whether to grant `NET_ADMIN`

## Quick Start

### 1) Pull image

```bash
docker pull ghcr.io/lipangeng/agent-runtime:main
```

### 2) Start a long-running container

```bash
docker run -d \
  --name codex-runtime \
  --init \
  -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/lipangeng/agent-runtime:main \
  bash
```

## Recommended Access Modes: Attach and Exec

Both `docker attach` and `docker exec` are recommended. Use them based on workload.

### Mode A: Attach (best for persistent interactive workflow)

```bash
docker attach codex-runtime
```

Pros:

- Session continuity feels like a long-lived local terminal.
- Works very well with `tmux` for persistent tasks.

Cons:

- You are directly attached to the container main process stdio.
- Shared usage by multiple operators can be harder to control.

### Mode B: Exec (best for ops and automation)

```bash
docker exec -it codex-runtime bash
```

Pros:

- Lower interference with the main process.
- Better for one-off commands, scripts, and team troubleshooting.

Cons:

- New shell process by default, no automatic continuity with main shell context.
- Long-running tasks still benefit from `tmux`.

Recommended pattern:

- Long-lived interactive dev: `attach + tmux`
- One-off ops/debug/automation: `exec`

## Recommended Session Manager: tmux

`tmux` is preinstalled and recommended.

Common flow:

```bash
tmux new -s agent
# detach: Ctrl+b then d
tmux attach -t agent
```

Pros:

- Recoverable sessions after terminal/network interruption.
- Multiple windows/panes for parallel tasks.
- Strong fit with attach-driven workflow.

Cons:

- Requires team conventions (naming, keybindings, lifecycle).
- Learning overhead for new users.
- Overusing one container for too many tasks may blur ownership boundaries.

## Network Acceleration with Sing-box (Sidecar/Namespace-sharing)

For agent workloads (model/package/code-host access), network quality directly impacts usability. A common pattern is a dedicated `sing-box` network container and agent containers sharing its network namespace.

### Core tun-mode DNS caveat

In tun mode, the common failure mode is Docker DNS priority. Docker's embedded DNS (`127.0.0.11`) may be preferred, so DNS queries do not enter `sing-box` tun processing.

What happens:

1. Container sends DNS queries to `127.0.0.11`.
2. DNS path bypasses `sing-box` tun inbound.
3. Proxy-domain DNS routing rules in `sing-box` are not applied.
4. Domains expected to be proxy-resolved may resolve to local-region IPs.
5. Actual traffic exits via remote proxy, causing resolution-egress mismatch and worse performance.

To make tun acceleration effective, both traffic routing and DNS routing must be controlled by `sing-box`.

Recommendations:

- Explicitly set DNS in deployment config to avoid fallback to `127.0.0.11`.
- Use `dns.servers`, `dns.rules`, and `hijack-dns` together in `sing-box`.
- Verify `/etc/resolv.conf` after start.

### Minimal compose shape

```yaml
services:
  CodeNet:
    image: ghcr.io/sagernet/sing-box:latest
    cap_add: [NET_ADMIN]
    sysctls:
      net.ipv4.ip_forward: "1"
    dns:
      - 10.10.0.254
    command: ["run", "-c", "/etc/sing-box/config.json"]

  codex:
    image: ghcr.io/lipangeng/agent-runtime:main
    network_mode: "service:CodeNet"
    depends_on: [CodeNet]
```

Notes:

- `NET_ADMIN` is required by `sing-box` in tun mode to create/manage TUN interfaces and routing rules.
- Grant `NET_ADMIN` only to the network container (`CodeNet`), not regular agent containers.
- In common bridge + namespace-sharing setups, these network changes are scoped to container namespaces and do not directly rewrite host global network config.

### Sanitized tun config example

```json
{
  "log": {
    "level": "info"
  },
  "dns": {
    "servers": [
      {
        "tag": "direct",
        "type": "udp",
        "server": "DIRECT_DNS_IP"
      },
      {
        "tag": "Mirror",
        "type": "udp",
        "server": "PROXY_DNS_IP",
        "detour": "Mirror"
      }
    ],
    "rules": [
      {
        "action": "route",
        "rule_set": "Mirror",
        "server": "Mirror"
      }
    ],
    "final": "direct",
    "reverse_mapping": true
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "sing-box",
      "interface_name": "sing-box",
      "address": ["172.18.0.1/24"],
      "mtu": 1450,
      "stack": "system",
      "auto_route": true,
      "strict_route": true,
      "auto_redirect": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "socks",
      "tag": "Mirror",
      "server": "PROXY_HOST_OR_IP",
      "server_port": 6000
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "action": "route",
        "rule_set": "Mirror",
        "outbound": "Mirror"
      }
    ],
    "rule_set": [
      {
        "type": "remote",
        "tag": "Mirror",
        "format": "binary",
        "url": "https://YOUR_RULESET_ENDPOINT/Mirror.srs"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": "direct"
  }
}
```

## Docker CLI and Rootless DinD Path

This base image does not include Docker CLI by default. Install Docker CLI in a derived image when needed.

Example:

```dockerfile
FROM ghcr.io/lipangeng/agent-runtime:main
USER root
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*
USER agent
```

### Option A: Host Docker socket mount

- Method: mount `/var/run/docker.sock`
- Pros: simple and fast
- Risk: effectively high host-level privilege exposure

### Option B: External rootless DinD (recommended for stronger isolation)

- Method: deploy rootless Docker engine separately and connect via `DOCKER_HOST`
- Pros: reduced host privilege impact
- Tradeoff: extra validation for network/storage/overlay behavior

Example:

```bash
export DOCKER_HOST=tcp://rootless-dind:2375
docker ps
```

## Deployment Scenarios

### 1) Local Docker (single machine)

Usage: run one or more agent containers directly with `docker run`.

Pros:

- fastest startup and debugging loop
- simplest bind-mount workflow

Cons:

- weaker multi-service orchestration
- network/security policy can drift across scripts

Best for: personal dev, PoC, temporary tasks.

### 2) Docker Compose (recommended for regular team setups)

Usage: define Codex/OpenCode/OpenClaw Gateway/network/state as services and volumes.

Pros:

- clear dependency/network/volume topology
- easier team standardization

Cons:

- mostly single-host focused
- config complexity higher than single container

Best for: small/medium teams, stable dev environments.

### 3) Kubernetes clusters

Usage: use Agent Runtime as base and split workloads via Deployment/StatefulSet/Job.

Pros:

- strong scheduling/scaling/recovery
- suitable for multi-tenant and elastic pools

Cons:

- higher operational complexity
- requires explicit design for persistence/session/network policy

Best for: platform teams and large-scale persistent operation.

### 4) OpenClaw clustered deployment

Recommended architecture:

1. separate Gateway layer with multiple replicas behind load balancing
2. run worker/CLI containers from this image with per-tenant/project isolation
3. use unified egress/proxy policy (`sing-box` or cluster egress)
4. control quotas, concurrency, and session lifecycle at orchestration layer

Pros:

- clean gateway/worker separation
- horizontal scaling by tenant/task class

Cons:

- requires governance for config drift, logs, workspace lifecycle
- requires strict image versioning and rollback discipline

## Security Notes

This image prioritizes operability. For production hardening:

- grant `NET_ADMIN` only to dedicated network containers
- some setups use `seccomp=unconfined` and `apparmor=unconfined` for `playwright-cli` compatibility; this is a functional tradeoff, not the final security posture
- a more restrictive browser-capable security profile is planned
- use least-privilege mounts and writable paths
- treat Docker socket mount as high risk; prefer external rootless engines where possible

## Recommendation: Use mise for Toolchain Management

`mise` is recommended for unified language/toolchain management.

Benefits:

- per-project version consistency across many repositories
- one management entrypoint for multiple toolchains (Node/Python/etc.)
- low switching cost across multi-project agent workloads

Current state:

- `mise` is installed and currently used to install Node LTS in the image
- full automatic environment switching is not enabled by default yet
- supporting skills/workflows are still evolving, so environment decisions are not yet as automated as desired

Suggested practice:

- keep explicit project-level `mise` config (`mise.toml` or `.tool-versions`)
- wrap build/test flows in reusable scripts to reduce environment drift

## CI/CD

GitHub Actions builds and pushes images to GHCR on push/PR.

- workflow: `.github/workflows/docker-build-and-push.yml`
- current platform: `linux/amd64`

## License

Licensed under Apache License 2.0. See `LICENSE`.
