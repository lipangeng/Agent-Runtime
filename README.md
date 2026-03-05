# Agent Runtime

一个面向 Agent 工具链的通用运行时基础镜像。

本项目的目标不是绑定单一产品，而是为 `Codex`、`OpenCode`、`OpenClaw` 等 Agent 类工具提供统一、可操作、可扩展的容器运行环境，并通过容器层与宿主环境实现隔离。

## 设计目标

- 提供开箱即用的基础运行环境，减少每个 Agent 单独配环境的重复成本。
- 预装常见调试与运维工具，便于在容器内直接排障与运维。
- 支持多 Agent 共用同一镜像，通过挂载不同目录隔离用户数据。
- 保持镜像层通用性：网络策略、权限模型、持久化策略由外部编排（如 Docker Compose）决定。

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

## 快速使用

### 1) 拉取镜像

```bash
docker pull ghcr.io/lipangeng/agent-runtime:main
```

### 2) 交互式进入容器

```bash
docker run --rm -it \
  -v "$PWD:/workspace" \
  -w /workspace \
  ghcr.io/lipangeng/agent-runtime:main \
  bash
```

### 3) 建议的连接方式

长期使用时优先：

```bash
docker exec -it <container_name> bash
```

相较 `docker attach`，`exec` 不会直接附着主进程 stdin/stdout，运维风险更低。

## Compose 集成建议

对于 Codex/OpenCode/OpenClaw 这类多实例场景，建议遵循：

- 每个 Agent 独立挂载自己的 home/config 目录。
- 共享 `/workspace` 作为项目代码目录。
- 网络和权限按最小授权原则分层配置。
- 尽量固定镜像版本（tag 或 digest），避免 `latest` 漂移。

## 安全建议

该镜像偏“可操作性优先”，默认包含较多运维工具。生产环境建议额外加固：

- 关闭不必要能力：避免默认使用 `NET_ADMIN`。
- 收敛安全例外：非必要不设置 `seccomp=unconfined`、`apparmor=unconfined`。
- 使用只读挂载与最小写权限目录。
- 为敏感目录单独卷并做好权限隔离。

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

当前仓库未声明许可证。若需公开分发，建议补充 `LICENSE`。
