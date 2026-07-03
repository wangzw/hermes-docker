# syntax=docker/dockerfile:1
#
# 增强版 Hermes Agent 镜像。
#
# 基础镜像 nousresearch/hermes-agent:<release> 是 NousResearch 官方 Dockerfile
# 在对应 release 上的多架构（amd64 + arm64）构建产物。这里只在其之上叠加一层
# 常用工具（vim / tmux / glab / claude code / opencode），不改动上游的 s6-overlay 启动链。
#
# 上游镜像 PID 1 是 s6-overlay 的 /init，ENTRYPOINT 为
#   ["/init", "/opt/hermes/docker/main-wrapper.sh"]
# 各服务由 s6 通过 `s6-setuidgid hermes` 降权运行。镜像最终用户即 root，
# 因此这里以 root 安装工具，且刻意不覆盖 ENTRYPOINT / CMD / USER。

ARG HERMES_VERSION=latest
FROM nousresearch/hermes-agent:${HERMES_VERSION}

# BuildKit 自动注入构建目标架构：amd64 / arm64
ARG TARGETARCH

USER root

# ---------- vim + tmux（上游为 debian:13 trixie，自带 apt） ----------
RUN apt-get update && \
    apt-get install -y --no-install-recommends vim tmux && \
    rm -rf /var/lib/apt/lists/*

# ---------- glab（GitLab CLI）官方二进制，按架构下载 ----------
# 版本通过 GLAB_VERSION 覆盖。tar.gz 内含 bin/glab。
ARG GLAB_VERSION=1.106.0
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64) glab_arch=amd64 ;; \
        arm64) glab_arch=arm64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH} for glab" >&2; exit 1 ;; \
    esac; \
    url="https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${glab_arch}.tar.gz"; \
    curl -fsSL --retry 3 -o /tmp/glab.tar.gz "$url"; \
    mkdir -p /tmp/glab; \
    tar -xzf /tmp/glab.tar.gz -C /tmp/glab; \
    install -m0755 "$(find /tmp/glab -type f -name glab | head -n1)" /usr/local/bin/glab; \
    rm -rf /tmp/glab /tmp/glab.tar.gz; \
    glab --version

# ---------- claude code CLI ----------
# 镜像已带 Node 22 + npm。claude-code v2 通过平台专属可选依赖 +
# postinstall(install.cjs) 装配对应架构的原生二进制；buildx 在目标架构下执行
# 本层，npm 会自动选对（debian=glibc，走非 musl 变体）。
RUN npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force && \
    command -v claude

# ---------- opencode CLI ----------
# opencode-ai 同样通过平台专属可选依赖装配原生二进制（debian=glibc，走非 musl 变体），
# buildx 在目标架构下执行本层，npm 自动选对。
RUN npm install -g opencode-ai && \
    npm cache clean --force && \
    command -v opencode

# ENTRYPOINT / CMD / USER 全部继承上游镜像，不在此覆盖。
