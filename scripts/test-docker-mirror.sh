#!/usr/bin/env bash
set -euo pipefail

echo "==> 测试 Docker 镜像加速器配置"
echo ""

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker 未运行，请先启动 Docker Desktop"
    exit 1
fi

echo "✅ Docker 正在运行"
echo ""

# 检查镜像加速器配置
echo "当前镜像加速器配置:"
docker info 2>/dev/null | grep -A 10 "Registry Mirrors" || echo "  未检测到镜像加速器配置（可能需要重启 Docker Desktop）"
echo ""

# 测试拉取镜像
echo "==> 测试拉取 node:22-bookworm 镜像"
echo ""

# 先尝试不使用摘要拉取
echo "尝试 1: 拉取 node:22-bookworm（不使用摘要）"
if docker pull node:22-bookworm 2>&1 | tee /tmp/docker-pull.log; then
    echo ""
    echo "✅ 镜像拉取成功！"
    exit 0
else
    echo ""
    echo "❌ 拉取失败，查看错误信息:"
    cat /tmp/docker-pull.log | tail -10
    echo ""
fi

# 检查是否是网络问题
echo "尝试 2: 测试镜像加速器连接性"
MIRRORS=(
    "https://docker.xuanyuan.me"
    "https://docker.1ms.run"
    "https://docker.m.daocloud.io"
    "https://hub.rat.dev"
    "https://docker.1panel.live"
    "https://dhub.kubesre.xyz"
    "https://hub.amingg.com"
    "https://docker.kejilion.pro"
    "https://docker.mirrors.ustc.edu.cn"
    "https://hub-mirror.c.163.com"
    "https://mirror.baidubce.com"
    "https://dockerproxy.com"
)

for mirror in "${MIRRORS[@]}"; do
    echo -n "测试 $mirror ... "
    if curl -s --connect-timeout 5 "$mirror" >/dev/null 2>&1; then
        echo "✅ 可访问"
    else
        echo "❌ 无法访问"
    fi
done

echo ""
echo "建议："
echo "1. 确保已重启 Docker Desktop 使配置生效"
echo "2. 如果镜像加速器无法访问，考虑使用方案 B：修改 Dockerfile 使用国内镜像源"
