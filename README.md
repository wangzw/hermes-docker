# hermes-docker

在 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 官方镜像基础上，
叠加常用工具（**vim / tmux / glab / claude code / opencode**）的增强版多架构镜像，
每周自动跟踪最新 release 构建并推送到 GitHub Container Registry。

- 镜像：`ghcr.io/wangzw/hermes-docker:latest`（也带 `:<hermes-release-tag>`）
- 架构：`linux/amd64` + `linux/arm64`
- 基础：官方 `nousresearch/hermes-agent:<release>`（即上游 Dockerfile 的多架构构建产物）

## 自动构建流水线

`.github/workflows/build.yml`：

1. **触发**：每周一 06:00 UTC（cron）、手动 `workflow_dispatch`、以及 `Dockerfile`/workflow/脚本变更 push。
2. `prepare`：通过 GitHub API 解析 `NousResearch/hermes-agent` 的最新 release tag（手动触发可用 `hermes_version` 覆盖）。
3. `build`（matrix）：**不使用 QEMU**。amd64 在 `ubuntu-24.04`、arm64 在 `ubuntu-24.04-arm` 原生 runner 上各自构建，
   本机原生跑**冒烟测试**（校验 vim/tmux/glab/claude/opencode 版本 + hermes 命令），通过后按 digest 推送到 GHCR。
4. `merge`：用 `docker buildx imagetools create` 把两个架构的 digest 合并成多架构 manifest，打 `<release-tag>` 与 `latest`，并校验 manifest 含 amd64+arm64。

镜像内容仅在官方镜像上追加一层工具，**不改动上游的 s6-overlay 启动链**（`ENTRYPOINT` / `CMD` / 服务降权均继承）。

## 部署

提供两种 compose：

| 文件 | 场景 |
| --- | --- |
| `docker-compose.yaml` | 本地/简单部署，直连主机端口，无 HTTPS |
| `docker-compose.https.yaml` | 生产部署：nginx 反代 + Let's Encrypt 自动 HTTPS |

### A. 本地/简单部署

```bash
cp .env.example .env                          # 填 LLM 密钥、DASHBOARD_USERNAME/PASSWORD、API_SERVER_KEY
cp data/config.yaml.example data/config.yaml  # 配置 provider/model
docker compose up -d
```

端口：

| 端口 | 用途 | 访问方式 |
| --- | --- | --- |
| 9119 | Dashboard（Web 控制台） | 用 `.env` 的 `DASHBOARD_USERNAME`/`DASHBOARD_PASSWORD` 登录 |
| 8642 | 网关 OpenAI 兼容 API | `Authorization: Bearer $API_SERVER_KEY` |

### B. 生产 HTTPS 部署（nginx 反代 + ACME）

`docker-compose.https.yaml` 用 `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion`
（底层 acme.sh）自动签发/续期 Let's Encrypt 证书，把 Dashboard 暴露在 `https://${DOMAIN}`。

前置条件：`${DOMAIN}` 解析到本机公网 IP，且 **80/443 端口可从公网访问**（ACME HTTP-01 挑战需要）。

```bash
cp .env.example .env   # 设置 DOMAIN / ACME_EMAIL / DASHBOARD_USERNAME / DASHBOARD_PASSWORD
docker compose -f docker-compose.https.yaml up -d
```

- Dashboard：`https://${DOMAIN}`，用 `.env` 用户名密码登录（nginx 终结 TLS，反代到容器内 9119）。
- 网关 API：仍直连主机 `8642`（Bearer 令牌保护）。
- 首次调试证书建议先启用 staging：在 `docker-compose.https.yaml` 的 `hermes.environment` 取消
  `LETSENCRYPT_TEST: "true"` 注释，避免触发 Let's Encrypt 生产环境频率限制；确认签发流程 OK 后再改回。

## 关键说明

- **必须以 `gateway run` 运行**（两个 compose 已设 `command: gateway run`）。这是 s6 监管下的长驻服务模式，
  同时拉起 gateway 与 dashboard；若不指定命令，容器会跑交互式 agent，无 TTY 时立即退出并拉垮整个容器。
- **Dashboard 认证走环境变量**：设 `HERMES_DASHBOARD=1` + `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`/`_PASSWORD`
  （即 `.env` 的 `DASHBOARD_USERNAME`/`DASHBOARD_PASSWORD`）。新版镜像对非 loopback 绑定强制要求认证，
  内置 basic provider 零基建满足，**无需再手动生成 `password_hash`**。
- **网关 API(8642) 默认关闭**：compose 已设 `API_SERVER_HOST=0.0.0.0`，只需在 `.env` 给 `API_SERVER_KEY`。
  验证：`curl -H "Authorization: Bearer $API_SERVER_KEY" http://localhost:8642/v1/models`。

## 本地构建 / 测试

```bash
# 取最新 release tag
TAG=$(gh api repos/NousResearch/hermes-agent/releases/latest --jq .tag_name)

# 构建本机架构并冒烟测试
docker buildx build --load --build-arg HERMES_VERSION="$TAG" -t hermes-enhanced:local .
./scripts/smoke-test.sh hermes-enhanced:local
```

## 新增工具版本

| 工具 | 来源 |
| --- | --- |
| vim / tmux | debian apt |
| glab (GitLab CLI) | 官方二进制（`GLAB_VERSION` ARG 可覆盖） |
| claude code | npm `@anthropic-ai/claude-code`（平台专属原生二进制） |
| opencode | npm `opencode-ai`（平台专属原生二进制） |
