#!/usr/bin/env bash
# 冒烟测试：校验增强镜像里新增的 5 个工具可执行，且 hermes 命令存在。
# 用 --entrypoint bash 绕过 s6-overlay /init，仅验证二进制本身。
#
# 用法：scripts/smoke-test.sh <image-ref>
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"

echo "==> 冒烟测试镜像：${IMAGE}"

docker run --rm --entrypoint bash "${IMAGE}" -c '
set -euo pipefail
echo "--- vim ---";    vim --version | head -n1
echo "--- tmux ---";   tmux -V
echo "--- glab ---";   glab --version | head -n1
echo "--- claude ---"; claude --version
echo "--- opencode ---"; opencode --version
echo "--- hermes ---"; command -v hermes
echo "SMOKE_OK"
' | tee /tmp/hermes-smoke.out

grep -q "SMOKE_OK" /tmp/hermes-smoke.out
echo "==> 冒烟测试通过 ✅"
