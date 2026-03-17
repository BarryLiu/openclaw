#!/usr/bin/env bash
set -euo pipefail

echo "==> Docker 镜像拉取问题诊断和修复"
echo ""

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker 未运行"
    echo "请先启动 Docker Desktop"
    exit 1
fi

echo "✅ Docker 正在运行"
echo ""

# 检查配置文件
DAEMON_JSON="$HOME/.docker/daemon.json"
if [[ ! -f "$DAEMON_JSON" ]]; then
    echo "❌ 配置文件不存在: $DAEMON_JSON"
    echo "运行配置脚本..."
    ./scripts/configure-docker-mirror.sh
    exit 0
fi

echo "✅ 配置文件存在: $DAEMON_JSON"
echo ""

# 检查配置是否生效
echo "当前 Docker 配置的镜像加速器:"
REGISTRY_MIRRORS=$(docker info 2>/dev/null | grep -A 20 "Registry Mirrors" || echo "")
if [[ -z "$REGISTRY_MIRRORS" ]]; then
    echo "⚠️  未检测到镜像加速器配置！"
    echo "配置文件可能未生效，需要重启 Docker Desktop"
    echo ""
    echo "正在重启 Docker Desktop..."
    
    # 重启 Docker Desktop
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'quit app "Docker"' 2>/dev/null || true
        echo "等待 Docker Desktop 关闭..."
        sleep 5
        open -a Docker
        echo "等待 Docker Desktop 启动..."
        sleep 10
        
        # 检查是否启动成功
        RETRY=0
        while ! docker info >/dev/null 2>&1 && [ $RETRY -lt 30 ]; do
            sleep 2
            RETRY=$((RETRY + 1))
        done
        
        if docker info >/dev/null 2>&1; then
            echo "✅ Docker Desktop 已重启"
        else
            echo "❌ Docker Desktop 启动超时，请手动启动"
            exit 1
        fi
    fi
else
    echo "$REGISTRY_MIRRORS"
fi

echo ""
echo "=========================================="
echo "测试镜像拉取"
echo "=========================================="
echo ""

# 测试拉取镜像
BASE_IMAGE="node:22-bookworm"
echo "测试拉取 $BASE_IMAGE..."

if docker pull "$BASE_IMAGE" 2>&1 | tee /tmp/docker-pull-test.log; then
    echo ""
    echo "✅ 镜像拉取成功！"
    echo ""
    echo "现在可以运行构建命令:"
    echo "  ./docker-setup.sh"
    exit 0
else
    echo ""
    echo "❌ 镜像拉取失败"
    echo ""
    echo "错误信息:"
    tail -20 /tmp/docker-pull-test.log 2>/dev/null || echo "无法获取错误信息"
    echo ""
    
    # 尝试从镜像源直接拉取
    echo "尝试从镜像源直接拉取..."
    MIRRORS=(
        "docker.xuanyuan.me"
        "docker.1ms.run"
        "docker.m.daocloud.io"
        "hub.rat.dev"
        "docker.1panel.live"
        "hub.amingg.com"
        "docker.kejilion.pro"
    )
    
    PULLED=false
    for mirror in "${MIRRORS[@]}"; do
        echo "尝试从 $mirror 拉取..."
        if docker pull "$mirror/library/$BASE_IMAGE" 2>/dev/null; then
            echo "✅ 成功从 $mirror 拉取镜像"
            docker tag "$mirror/library/$BASE_IMAGE" "$BASE_IMAGE" 2>/dev/null || true
            PULLED=true
            break
        fi
    done
    
    if [[ "$PULLED" == "true" ]]; then
        echo ""
        echo "✅ 镜像拉取成功！"
        echo ""
        echo "现在可以运行构建命令:"
        echo "  ./docker-setup.sh"
        exit 0
    else
        echo ""
        echo "❌ 所有镜像源都无法拉取"
        echo ""
        echo "可能的解决方案:"
        echo "1. 检查网络连接"
        echo "2. 检查防火墙设置"
        echo "3. 尝试使用 VPN 或代理"
        echo "4. 手动下载镜像文件并导入"
        echo ""
        echo "手动导入镜像的方法:"
        echo "  1. 从其他可访问 Docker Hub 的机器导出镜像:"
        echo "     docker save node:22-bookworm | gzip > node-22-bookworm.tar.gz"
        echo "  2. 传输到当前机器后导入:"
        echo "     gunzip -c node-22-bookworm.tar.gz | docker load"
        exit 1
    fi
fi
