#!/usr/bin/env bash
set -euo pipefail

echo "==> 测试 Docker 镜像加速器连接性"
echo ""

# 定义所有镜像加速器地址
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

AVAILABLE_MIRRORS=()
UNAVAILABLE_MIRRORS=()

echo "正在测试镜像加速器连接性..."
echo ""

for mirror in "${MIRRORS[@]}"; do
    echo -n "测试 $mirror ... "
    
    # 测试 HTTP 连接（超时 5 秒）
    if curl -s --connect-timeout 5 --max-time 10 "$mirror" >/dev/null 2>&1 || \
       curl -s --connect-timeout 5 --max-time 10 "$mirror/v2/" >/dev/null 2>&1; then
        echo "✅ 可访问"
        AVAILABLE_MIRRORS+=("$mirror")
    else
        echo "❌ 无法访问"
        UNAVAILABLE_MIRRORS+=("$mirror")
    fi
done

echo ""
echo "=========================================="
echo "测试结果汇总："
echo "=========================================="
echo ""
echo "✅ 可用的镜像加速器 (${#AVAILABLE_MIRRORS[@]} 个):"
for mirror in "${AVAILABLE_MIRRORS[@]}"; do
    echo "  - $mirror"
done

if [ ${#UNAVAILABLE_MIRRORS[@]} -gt 0 ]; then
    echo ""
    echo "❌ 不可用的镜像加速器 (${#UNAVAILABLE_MIRRORS[@]} 个):"
    for mirror in "${UNAVAILABLE_MIRRORS[@]}"; do
        echo "  - $mirror"
    done
fi

echo ""
echo "=========================================="
echo "建议配置："
echo "=========================================="
echo ""

if [ ${#AVAILABLE_MIRRORS[@]} -gt 0 ]; then
    echo "建议只保留可用的镜像加速器，更新配置文件："
    echo ""
    echo "文件路径: ~/.docker/daemon.json"
    echo ""
    echo "建议的配置内容："
    echo "{"
    echo "  \"builder\": {"
    echo "    \"gc\": {"
    echo "      \"defaultKeepStorage\": \"20GB\","
    echo "      \"enabled\": true"
    echo "    }"
    echo "  },"
    echo "  \"experimental\": false,"
    echo "  \"registry-mirrors\": ["
    for i in "${!AVAILABLE_MIRRORS[@]}"; do
        if [ $i -eq $((${#AVAILABLE_MIRRORS[@]} - 1)) ]; then
            echo "    \"${AVAILABLE_MIRRORS[$i]}\""
        else
            echo "    \"${AVAILABLE_MIRRORS[$i]}\","
        fi
    done
    echo "  ]"
    echo "}"
else
    echo "⚠️  警告：没有找到可用的镜像加速器！"
    echo "可能的原因："
    echo "  1. 网络连接问题"
    echo "  2. 防火墙阻止"
    echo "  3. 所有镜像源暂时不可用"
    echo ""
    echo "建议："
    echo "  1. 检查网络连接"
    echo "  2. 稍后重试"
    echo "  3. 考虑使用代理或 VPN"
fi

echo ""
echo "=========================================="
echo "测试 Docker 镜像拉取"
echo "=========================================="
echo ""

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo "⚠️  Docker 未运行，跳过镜像拉取测试"
    echo "请先启动 Docker Desktop"
    exit 0
fi

echo "检查 Docker 镜像加速器配置..."
docker info 2>/dev/null | grep -A 15 "Registry Mirrors" || echo "  未检测到镜像加速器配置（可能需要重启 Docker Desktop）"
echo ""

echo "测试拉取 node:22-bookworm 镜像..."
if docker pull node:22-bookworm 2>&1 | tee /tmp/docker-pull-test.log; then
    echo ""
    echo "✅ 镜像拉取成功！"
    echo ""
    echo "查看使用的镜像源："
    docker info 2>/dev/null | grep -A 15 "Registry Mirrors" || echo "无法获取镜像源信息"
else
    echo ""
    echo "❌ 镜像拉取失败"
    echo ""
    echo "错误信息："
    tail -10 /tmp/docker-pull-test.log 2>/dev/null || echo "无法获取错误信息"
    echo ""
    echo "建议："
    echo "  1. 确保已重启 Docker Desktop"
    echo "  2. 检查网络连接"
    echo "  3. 尝试手动拉取: docker pull node:22-bookworm"
fi
