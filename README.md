# hermes-docker

在 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 官方镜像基础上，
叠加常用工具（**vim / tmux / glab / claude code**）的增强版多架构镜像，
每周自动跟踪最新 release 构建并推送到 GitHub Container Registry。

- 镜像：`ghcr.io/wangzw/hermes-docker:latest`（也带 `:<hermes-release-tag>`）
- 架构：`linux/amd64` + `linux/arm64`
- 基础：官方 `nousresearch/hermes-agent:<release>`（即上游 Dockerfile 的多架构构建产物）

## 自动构建流水线

`.github/workflows/build.yml`：

1. **触发**：每周一 06:00 UTC（cron）、手动 `workflow_dispatch`、以及 `Dockerfile`/workflow/脚本变更 push。
2. 通过 GitHub API 解析 `NousResearch/hermes-agent` 的最新 release tag（手动触发可用 `hermes_version` 覆盖）。
3. 先在 amd64 上 `--load` 构建并跑**冒烟测试**（校验 vim/tmux/glab/claude 版本 + hermes 命令）。
4. 冒烟通过后，多架构（amd64+arm64）构建并推送到 GHCR，打 `<release-tag>` 与 `latest` 两个 tag。

镜像内容仅在官方镜像上追加一层工具，**不改动上游的 s6-overlay 启动链**（`ENTRYPOINT` / `CMD` / 服务降权均继承）。

## 部署

```bash
cp .env.example .env                          # 填入 LLM 密钥、API_SERVER_KEY
cp data/config.yaml.example data/config.yaml  # 配置 provider/model 与 dashboard 认证
docker compose up -d
```

端口：

| 端口 | 用途 |
| --- | --- |
| 9119 | Dashboard（Web 控制台） |
| 8642 | 网关 OpenAI 兼容 API |

## ⚠️ 两个已知坑

1. **Dashboard(9119) 默认无法从宿主访问。** 新版镜像在无认证时拒绝绑定 `0.0.0.0`（否则崩溃重启刷屏
   `Refusing to bind dashboard to 0.0.0.0`）。宿主端口映射又要求容器内绑 `0.0.0.0`，所以**必须配 basic auth**：
   在 `data/config.yaml` 设 `dashboard.basic_auth.username` + `password_hash`。
   生成 hash：
   ```bash
   docker compose exec hermes \
     python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('你的密码'))"
   ```

2. **网关 OpenAI 兼容 API(8642) 默认关闭。** 需设 `API_SERVER_HOST=0.0.0.0`（compose 已设）+ `API_SERVER_KEY`（写进 `.env`）。
   开启后可验证：
   ```bash
   curl -H "Authorization: Bearer $API_SERVER_KEY" http://localhost:8642/v1/models
   ```

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
