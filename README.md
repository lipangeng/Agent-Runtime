# Agent Runtime

一个面向 Agent 工具链的通用运行时基础镜像。

本项目的目标不是绑定单一产品，而是为 `Codex`、`OpenCode`、`OpenClaw` 等 Agent 类工具提供统一、可操作、可扩展的容器运行环境，并通过容器层与宿主环境实现隔离。

## 设计目标

- 提供开箱即用的基础运行环境，减少每个 Agent 单独配环境的重复成本。
- 预装常见调试与运维工具，便于在容器内直接排障与运维。
- 支持多 Agent 共用同一镜像，通过挂载不同目录隔离用户数据。
- 保持镜像层通用性：网络策略、权限模型、持久化策略由外部编排（如 Docker Compose、Kubernetes）决定。

## 当前镜像内容

基础镜像：`debian:latest`

预装能力（节选）：

- Shell 与基础工具：`bash`、`zsh`、`fish`、`sudo`、`tmux`、`coreutils`
- 诊断与网络：`tcpdump`、`strace`、`lsof`、`nmap`、`iproute2`、`dnsutils`
- 开发工具：`git`、`gh`、`python3`、`pip`、`cmake`、`jq`
- Node 运行时：通过 `mise` 安装 `Node LTS`
- 浏览器自动化：`playwright` + `chrome`

默认用户：`agent`（uid/gid: `1024`）  
默认工作目录：`/workspace`

## 仓库边界

本仓库只维护“基础镜像”本身，不直接定义你的生产拓扑。  
例如：

- 是否走代理/隧道网络
- 是否使用 `network_mode: service:*`
- 是否启用 `seccomp=unconfined` / `apparmor=unconfined`
- 是否授予 `NET_ADMIN`

这些属于部署侧策略，应由外部编排文件按场景设置。

## 快速开始

### 1) 拉取镜像

```bash
docker pull ghcr.io/lipangeng/agent-runtime:main
```

### 2) 本地启动一个长期容器

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

## 推荐连接方式：Attach 与 Exec

`docker attach` 与 `docker exec` 都是本项目推荐方式，二者适用于不同场景。

### 方式 A：Attach（长期会话优先）

```bash
docker attach codex-runtime
```

特点：直接附着到容器主进程，适合“容器就是长期在线终端”的使用习惯。只要容器不退出，下次 attach 回来时上下文仍在（配合 `tmux` 效果最好）。

优点：

- 会话连续性强，终端体验接近“永不掉线”。
- 与 `tmux` 结合后可以稳定维护长期任务。

缺点：

- 直接绑定主进程 stdin/stdout，误操作影响面更大。
- 多人同时 attach 同一主进程时，交互边界不清晰。

### 方式 B：Exec（运维与自动化优先）

```bash
docker exec -it codex-runtime bash
```

特点：在容器内启动新的进程，不直接接管主进程终端。

优点：

- 对主进程干扰更小，适合运维检查和一次性命令。
- 更适合脚本化、自动化和多人协作排障。

缺点：

- 默认是“新 shell”，不天然继承主会话上下文。
- 长期工作流通常仍需 `tmux` 保持任务状态。

建议：

- 长期交互开发：`attach + tmux`。
- 运维排障/自动化执行：`exec`。
- 配置 `--restart unless-stopped`，避免机器重启后容器消失。

## 推荐会话管理：tmux

镜像已内置 `tmux`，建议作为默认会话管理器。

### 常用方式

首次进入后创建会话：

```bash
tmux new -s agent
```

断开但不结束任务：

```bash
# Ctrl+b 然后 d
```

重连：

```bash
tmux attach -t agent
```

### 优缺点

优点：

- 会话可恢复：网络断开、终端关闭后任务不丢。
- 多窗口并行：一个容器内可并行运行构建、日志、交互命令。
- 与 `attach` 组合后，形成“永久在线工作台”。

缺点：

- 需要团队统一快捷键和会话命名规范。
- 新成员有学习成本。
- 如果滥用单容器多任务，可能导致职责边界不清晰。

## 网络加速方案：Sing-box 旁路代理

对于 Agent 场景（拉模型、拉 npm/pip 包、访问代码托管），网络质量直接影响可用性。推荐通过独立 `sing-box` 网络容器提供出口代理，再让 Agent 容器复用该网络栈。

### 设计思路

1. 单独部署 `sing-box` 容器，负责路由、DNS、策略分流。
2. Agent 容器使用 `network_mode: service:<sing-box-service>` 共享网络命名空间。
3. 将 DNS 指向 `sing-box` 内部 DNS 或你定义的上游。
4. 在 `sing-box` 内实现分流规则（直连/代理/拦截），避免全量代理导致延迟放大。

### 关键注意：Tun 模式下必须处理 Docker 默认 DNS

在 `tun` 模式里，最常见的问题不是“忘记配 DNS 规则”，而是 Docker 默认 DNS（通常是 `127.0.0.11`）优先级更高。

结果是：

1. 容器先把 DNS 请求发给 `127.0.0.11`（Docker 内置 DNS）。
2. 这个查询路径不会进入 `sing-box` 的 `tun` 入站。
3. 你在 `sing-box` 里配置的代理解析/分流解析规则不生效。
4. 某些应走代理解析的域名被解析为本地出口更“近”的 IP。
5. 实际连接却走远端代理出口，解析与访问出口错位，速度反而变慢。

结论：`tun` 模式要实现稳定加速，必须同时保证“流量进 tun”与“DNS 查询也受 sing-box 管控”。

推荐做法：

- 在编排层显式设置 DNS，避免容器落回 `127.0.0.11`。
- 在 `sing-box` 中配置 `dns.servers`、`dns.rules` 与 `hijack-dns` 协同工作。
- 启动后检查 `/etc/resolv.conf`，确认不是 Docker 内置回环 DNS。

### 参考 Compose 结构（最小示意）

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

### 参考配置（脱敏示例，基于你的 tun 方案）

以下示例已做脱敏处理，可作为结构参考：

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

### 价值与代价

价值：

- 统一出口策略，多个 Agent 共享网络规则。
- 对跨境或高抖动网络场景可显著改善拉取速度和稳定性。
- 不改 Agent 工具本身即可获得网络治理能力。

代价：

- 网络问题排查复杂度上升（应用层 + 代理层）。
- 需要额外维护 `sing-box` 规则与证书。
- `NET_ADMIN` 等能力应严格收敛在网络容器，不要扩散到所有 Agent 容器。

## Docker CLI 与 Rootless DinD 可行性

当前基础镜像未默认内置 `docker` 客户端。推荐通过二次构建安装 Docker CLI，再将该容器作为“控制平面容器”连接外部或旁路 Docker 引擎。

示意 Dockerfile：

```dockerfile
FROM ghcr.io/lipangeng/agent-runtime:main
USER root
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*
USER agent
```

### 方式 A：挂载宿主 Docker Socket

- 做法：挂载 `/var/run/docker.sock`，容器内直接执行 `docker`。
- 优点：性能好、配置简单。
- 风险：容器几乎等价于宿主 root 权限，不适合高隔离场景。

### 方式 B：对接 Rootless DinD（推荐用于隔离诉求）

- 做法：单独部署 rootless Docker 引擎容器，Agent 仅通过 `DOCKER_HOST` 连接该引擎。
- 优点：降低对宿主权限冲击，适合多租户/高隔离。
- 代价：网络、存储、overlay 性能与兼容性需要额外验证。

示意：

```bash
export DOCKER_HOST=tcp://rootless-dind:2375
docker ps
```

结论：本项目不内置 DinD，但为“Docker CLI + 外置 rootless 引擎”提供可行基础。

## 适用场景与部署模式

### 模式 1：本地单机 Docker

使用方式：个人开发机直接 `docker run` 启动一个或多个 Agent 容器。

优点：

- 启动快，调试最直接。
- 与本地目录映射简单。

缺点：

- 多实例编排能力弱。
- 网络与权限策略容易散落在脚本中。

适用：个人开发、PoC、临时任务。

### 模式 2：Docker Compose（推荐常规团队场景）

使用方式：按角色定义多个服务（Codex、OpenCode、OpenClaw Gateway、网络容器、卷）。

优点：

- 多服务关系（依赖、共享网络、卷）表达清晰。
- 易于固化团队标准运行方式。

缺点：

- 单机为主，跨主机扩展有限。
- 配置复杂度高于单容器。

适用：小中型团队、稳定开发环境、网关与代理组合部署。

### 模式 3：Kubernetes 集群

使用方式：将 Agent Runtime 作为基础镜像，按工作负载拆分 Deployment/StatefulSet/Job。

优点：

- 调度、扩缩容、故障恢复能力强。
- 适合多项目、多租户、弹性任务池。

缺点：

- 运维门槛高。
- 需要额外设计持久化、会话恢复、网络策略。

适用：平台化团队、统一 Agent 集群、长期稳定运行。

### 模式 4：OpenClaw 集群化部署（重点场景）

推荐思路：

1. Gateway 层独立部署，多副本并挂负载均衡。
2. 每个 Worker/CLI 使用本镜像，按项目或租户隔离 `workspace` 与配置目录。
3. 网络侧接入统一代理层（如 `sing-box`）或集群 egress 网关。
4. 在编排层控制资源配额（CPU/内存/并发）与会话生命周期。

优点：

- 清晰的网关/执行层分离。
- 可按租户或任务类型横向扩展。

缺点：

- 需要治理配置漂移、日志聚合、工作目录生命周期。
- 需要规范化镜像版本与回滚策略。

可选落地方式：

- Compose：适合单机或少量节点，快速搭建 OpenClaw Gateway + Worker。
- Kubernetes：适合多节点和高并发，通过 HPA/队列化任务做弹性扩容。

## 安全建议

该镜像偏“可操作性优先”，生产环境建议额外加固：

- 关闭不必要能力：避免默认使用 `NET_ADMIN`。
- 收敛安全例外：非必要不设置 `seccomp=unconfined`、`apparmor=unconfined`。
- 使用只读挂载与最小写权限目录。
- 为敏感目录单独卷并做好权限隔离。
- 若使用 Docker Socket，明确其高权限风险；优先考虑 rootless 外置引擎。

## CI/CD

GitHub Actions 在 push/pr 时构建并推送镜像到 GHCR：

- 工作流文件：`.github/workflows/docker-build-and-push.yml`
- 当前构建平台：`linux/amd64`

## 自定义扩展

如需为特定 Agent 增加依赖，建议：

1. 基于本镜像二次构建（`FROM ghcr.io/lipangeng/agent-runtime:<tag>`）。
2. 将产品专属依赖放入上层镜像，保持基础镜像稳定。
3. 用不同 tag 管理运行时变体（例如 `codex`, `opencode`, `openclaw`）。

## 许可证

本项目使用 Apache License 2.0，详见 `LICENSE`。
