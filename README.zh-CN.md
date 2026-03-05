# Agent Runtime

一个面向 Agent 工具链的通用运行时基础镜像。

语言版本：

- English（默认）: `README.md`
- 简体中文: `README.zh-CN.md`

## 快速概览

`Agent-Runtime` 是一个面向 AI Agent 工具链的通用基础运行时镜像。  
它提供一致的容器环境，内置调试工具、浏览器自动化支持，以及可直接落地的部署模式。

该运行时不绑定特定框架，可用于：

- `Codex`
- `OpenCode`
- `OpenClaw`
- 其他自定义 Agent 系统

## 项目存在的原因

在实践 Agent 工具链时，常见问题包括：

- 容器内缺少调试工具
- 浏览器自动化依赖脆弱、易出问题
- 文件挂载与读写权限策略不清晰
- 网络与代理配置复杂且容易失效

`Agent-Runtime` 的目标是提供一个务实的基础镜像来解决这些问题。

## 关键特性

- 默认非 root 用户运行
- 常见诊断工具齐全（`tcpdump`、`strace`、`nmap` 等）
- 常见开发工具齐全（`git`、`python`、`pip`、`jq`、`cmake`）
- `Node.js LTS` 运行环境
- `Playwright + Chrome` 就绪
- 内置 `tmux`，便于交互式调试
- 结构化 Entrypoint 流程（`/entrypoint.d/system` + `/entrypoint.d/user`），便于运行时初始化
- 启动命令更容易定制，无需频繁重建定制镜像
- 降低多运行时变体的长期维护成本
- 便于与 Agent SKILL 设想配合，记录环境需求并在重启后恢复环境一致性

## 设计理念

`Agent-Runtime` 有意不实现 Agent 框架本身。  
它专注运行时层，编排、隔离与策略由下层平台负责：

- Docker
- Docker Compose
- Kubernetes

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
  -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/lipangeng/agent-runtime:main \
  bash
```

## 容器 Entrypoint 机制

镜像当前使用：

- `ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]`
- `CMD ["bash"]`

其中 `tini` 作为 PID 1，负责信号转发与僵尸进程回收；`entrypoint.sh` 负责初始化流程，然后再执行主命令。

### 采用该设计的原因

这套入口机制的设计目标是：

- 让运行环境初始化更简单、可重复
- 让启动命令的定制更容易，不必频繁重建镜像层
- 降低维护大量定制镜像的成本

### 执行流程

1. 可选展示使用提示：`/entrypoint.d/usage.sh`（存在才执行）
2. 执行系统初始化脚本：`/entrypoint.d/system/*`
3. 执行用户初始化脚本：`/entrypoint.d/user/*`
4. 执行最终主命令（来自 `CMD` 或运行时参数）

### 初始化脚本规则

- 按版本顺序处理（`sort -V`）
- 只处理 `*.sh` 文件
- 可执行的 `*.sh`：直接执行
- 不可执行的 `*.sh`：使用 `source` 导入当前 shell

这样可以同时支持“子进程执行脚本”和“修改当前 shell 环境”两种模式。

### Entrypoint 控制项（环境变量）

- `SKIP_SYSTEM_ENTRYPOINT=1`：跳过 `/entrypoint.d/system/*`
- `SKIP_USER_ENTRYPOINT=1`：跳过 `/entrypoint.d/user/*`
- `REAL_ENTRYPOINT=/path/to/script-or-binary`：初始化后转交给真实入口继续执行

如果设置了 `REAL_ENTRYPOINT` 但文件不存在或不可读，容器会快速失败退出。

### 命令执行模式

初始化完成后：

- 如果第一个参数是有效命令（`command -v` 成功），执行 `exec "$@"`
- 否则回退到 shell 解析模式：`exec /bin/sh -c "exec $*"`

回退模式适合某些平台只传单字符串命令的场景。

### 实用示例

挂载初始化脚本目录：

```bash
docker run --rm -it \
  -v "$PWD/entrypoint.d/system:/entrypoint.d/system:ro" \
  -v "$PWD/entrypoint.d/user:/entrypoint.d/user:ro" \
  ghcr.io/lipangeng/agent-runtime:main
```

跳过系统与用户初始化：

```bash
docker run --rm -it \
  -e SKIP_SYSTEM_ENTRYPOINT=1 \
  -e SKIP_USER_ENTRYPOINT=1 \
  ghcr.io/lipangeng/agent-runtime:main bash
```

转交到自定义真实入口：

```bash
docker run --rm -it \
  -e REAL_ENTRYPOINT=/usr/local/bin/custom-entrypoint.sh \
  ghcr.io/lipangeng/agent-runtime:main -- my-app --flag value
```

### 与 Agent SKILL 的后续配合方向

面向 Agent 工作流，这套机制后续可以与 SKILL 配合：

- 让 Agent 记录项目所需的环境依赖
- 让 Agent 自动生成/更新 `/entrypoint.d/user/` 下的初始化脚本
- 在后续重启时，通过这些脚本快速恢复一致的环境状态

这样可以提升重启后的环境一致性，尤其适用于多项目并行的 Agent 场景。

### SKILL 示例设想（仅为想法）

这一部分目前仍是设想，不是内置完成能力。

可能的 SKILL 行为：

1. 扫描当前项目所需的运行时与工具（Node/Python/系统包）
2. 生成确定性的初始化脚本，例如 `/entrypoint.d/user/20-project-env.sh`
3. 写入或更新项目环境元数据，方便审查和复用
4. 下次重启时由 entrypoint 自动回放脚本，恢复同一环境基线

SKILL 可能生成的最小脚本示例：

```bash
#!/usr/bin/env bash
set -e
mise use -g node@20
python3 -m pip install -r /workspace/requirements.txt
```

示例场景：

- 第一天：Agent 分析项目依赖并生成 `20-project-env.sh`
- 第二天：容器重启或被重新调度，entrypoint 自动执行该脚本
- 结果：运行时与工具链基线快速恢复，减少人工初始化和环境漂移

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

说明：

- `NET_ADMIN` 是 `sing-box` 容器在 `tun` 模式下的必要权限，用于创建/配置 TUN 设备和路由规则。
- 该权限应只授予网络容器（如 `CodeNet`），不应授予普通 Agent 容器。
- 在桥接网络和 `network_mode: service:*` 的常见部署下，这些网络变更作用于容器网络命名空间，不会直接改写宿主机全局网络配置。

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

- 关闭不必要能力：`NET_ADMIN` 仅授予 `sing-box` 等网络容器，不要给普通 Agent 容器。
- 当前部分场景为兼容 `playwright-cli` 会使用 `seccomp=unconfined`、`apparmor=unconfined`；这是功能优先的折中，不建议默认全量开启。
- 后续会提供更细粒度方案，在保证 Agent 可使用浏览器能力的前提下，尽量减少权限开放范围。
- 使用只读挂载与最小写权限目录。
- 为敏感目录单独卷并做好权限隔离。
- 若使用 Docker Socket，明确其高权限风险；优先考虑 rootless 外置引擎。

## 文件系统访问策略（只读 / 可读写）

Agent 任务通常需要访问项目文件。基于 Docker 的最佳实践是显式区分只读挂载与可写挂载路径。

### 为什么需要这层控制

- 限制错误命令或异常脚本导致的破坏范围。
- 降低误覆盖、误删除宿主项目文件的风险。
- 让“哪里可写”在配置层可审计、可排查。

### 推荐模型

- 代码和配置默认只读挂载。
- 单独提供可写目录用于产物、缓存、临时文件。
- 尽量开启容器根文件系统只读，再按需开放最小写路径。

### 本地 Docker 示例

项目只读 + 输出目录可写：

```bash
docker run --rm -it \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=512m \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.agent-output:/workspace/.agent-output:rw" \
  -w /workspace \
  ghcr.io/lipangeng/agent-runtime:main \
  bash
```

当 Agent 必须改动仓库文件时：

```bash
docker run --rm -it \
  -v "$PWD:/workspace:rw" \
  -w /workspace \
  ghcr.io/lipangeng/agent-runtime:main \
  bash
```

### Docker Compose 示例

```yaml
services:
  codex:
    image: ghcr.io/lipangeng/agent-runtime:main
    read_only: true
    tmpfs:
      - /tmp:size=512m
    volumes:
      - ./project:/workspace:ro
      - ./agent-output:/workspace/.agent-output:rw
```

如果确实需要写回项目，仅将项目挂载改为 `:rw`，其他路径继续收敛权限。

### Kubernetes 示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: agent-runtime
spec:
  containers:
    - name: agent
      image: ghcr.io/lipangeng/agent-runtime:main
      securityContext:
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: project
          mountPath: /workspace
          readOnly: true
        - name: agent-output
          mountPath: /workspace/.agent-output
  volumes:
    - name: project
      persistentVolumeClaim:
        claimName: project-pvc
    - name: agent-output
      emptyDir: {}
```

### 场景建议

- 只读审查/分析任务：项目 `ro`，输出目录 `rw`。
- CI 报告生成：项目 `ro`，报告与日志目录 `rw`。
- 重构/代码生成任务：项目 `rw`，但根文件系统与无关路径继续最小化可写权限。
- 多租户共享宿主：优先项目默认 `ro`，按租户显式分配独立可写目录。

## Mise 使用建议

本项目建议使用 `mise` 统一管理语言与构建工具版本。

主要优势：

- 多项目一致性：不同仓库可通过配置文件声明各自版本，减少“我这里能跑你那里不行”。
- 多语言统一入口：Node、Python 等工具链可以统一由 `mise` 管理。
- 版本切换成本低：项目切换时可快速切换运行时，适合 Agent 同机处理多个项目。

当前状态：

- 镜像已安装 `mise` 并用于安装 Node LTS。
- 尚未默认启用完整的自动配置/自动环境切换工作流。
- 目前也缺少一套成熟的配套 skill 来自动引导 Agent 做环境决策，因此“智能化程度”仍有提升空间。

推荐实践：

- 在项目仓库中显式维护 `mise` 配置（如 `mise.toml` 或 `.tool-versions`）。
- 将构建命令封装为可复用脚本，减少 Agent 在多项目场景下的环境判断成本。

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
