#!/usr/bin/env bash
set -euo pipefail

# Docker 镜像加速器配置脚本
# 此脚本会自动配置 Docker daemon.json 以使用国内镜像源

echo "==> 配置 Docker 镜像加速器"

# 检测操作系统
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Docker Desktop)
    DAEMON_JSON="$HOME/.docker/daemon.json"
    DOCKER_CONFIG_DIR="$HOME/.docker"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    DAEMON_JSON="/etc/docker/daemon.json"
    DOCKER_CONFIG_DIR="/etc/docker"
else
    echo "ERROR: 不支持的操作系统: $OSTYPE" >&2
    exit 1
fi

# 创建配置目录（如果不存在）
mkdir -p "$DOCKER_CONFIG_DIR"

# 定义镜像加速器列表（多个备用，按优先级排序）
# 2026年最新可用的国内镜像加速器地址
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

# 读取现有配置（如果存在）
EXISTING_CONFIG="{}"
if [[ -f "$DAEMON_JSON" ]]; then
    echo "发现现有配置文件: $DAEMON_JSON"
    echo "当前配置内容:"
    cat "$DAEMON_JSON"
    echo ""
    
    # 备份现有配置
    BACKUP_FILE="${DAEMON_JSON}.bak.$(date +%Y%m%d_%H%M%S)"
    if cp "$DAEMON_JSON" "$BACKUP_FILE" 2>/dev/null; then
        echo "已备份现有配置到: $BACKUP_FILE"
    else
        echo "警告: 无法创建备份文件（可能权限不足）"
    fi
    
    # 读取现有配置
    if command -v python3 >/dev/null 2>&1; then
        EXISTING_CONFIG=$(python3 -c "import json, sys; print(json.dumps(json.load(open('$DAEMON_JSON'))))" 2>/dev/null || echo "{}")
    elif command -v node >/dev/null 2>&1; then
        EXISTING_CONFIG=$(node -e "console.log(JSON.stringify(require('fs').readFileSync('$DAEMON_JSON', 'utf8') ? JSON.parse(require('fs').readFileSync('$DAEMON_JSON', 'utf8')) : {}))" 2>/dev/null || echo "{}")
    fi
    
    # 检查是否已配置镜像加速器
    if grep -q "registry-mirrors" "$DAEMON_JSON" 2>/dev/null; then
        echo "检测到已存在镜像加速器配置"
        read -p "是否要更新镜像加速器配置? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已取消配置"
            exit 0
        fi
    fi
else
    echo "创建新配置文件: $DAEMON_JSON"
fi

# 创建临时文件
TMP_FILE=$(mktemp)

# 合并配置：保留现有设置，更新镜像加速器
if command -v python3 >/dev/null 2>&1; then
    python3 <<PYTHON_SCRIPT > "$TMP_FILE"
import json
import sys

# 读取现有配置
try:
    with open("$DAEMON_JSON", "r", encoding="utf-8") as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

# 更新镜像加速器配置（2026年最新可用地址）
config["registry-mirrors"] = [
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://hub.rat.dev",
    "https://docker.1panel.live",
    "https://dhub.kubesre.xyz",
    "https://hub.amingg.com",
    "https://docker.kejilion.pro",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerproxy.com"
]

# 确保其他重要配置保留
if "experimental" not in config:
    config["experimental"] = False
if "insecure-registries" not in config:
    config["insecure-registries"] = []
if "builder" not in config:
    config["builder"] = {}

print(json.dumps(config, indent=2, ensure_ascii=False))
PYTHON_SCRIPT
elif command -v node >/dev/null 2>&1; then
    node <<NODE_SCRIPT > "$TMP_FILE"
const fs = require('fs');
let config = {};
try {
    config = JSON.parse(fs.readFileSync("$DAEMON_JSON", "utf8"));
} catch (e) {
    config = {};
}

config["registry-mirrors"] = [
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://hub.rat.dev",
    "https://docker.1panel.live",
    "https://dhub.kubesre.xyz",
    "https://hub.amingg.com",
    "https://docker.kejilion.pro",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerproxy.com"
];

if (!config.experimental) config.experimental = false;
if (!config["insecure-registries"]) config["insecure-registries"] = [];
if (!config.builder) config.builder = {};

console.log(JSON.stringify(config, null, 2));
NODE_SCRIPT
else
    # 如果没有 Python 或 Node.js，使用简单的 JSON 构造
    cat > "$TMP_FILE" <<JSON
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://hub.rat.dev",
    "https://docker.1panel.live",
    "https://dhub.kubesre.xyz",
    "https://hub.amingg.com",
    "https://docker.kejilion.pro",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerproxy.com"
  ],
  "experimental": false
}
JSON
fi

# 验证 JSON 格式
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -m json.tool "$TMP_FILE" >/dev/null 2>&1; then
        echo "ERROR: 生成的 JSON 配置格式无效" >&2
        rm -f "$TMP_FILE"
        exit 1
    fi
fi

# 显示新配置
echo ""
echo "新配置内容:"
cat "$TMP_FILE"
echo ""

# 如果是系统级配置（Linux），需要 sudo
if [[ "$DAEMON_JSON" == "/etc/docker/daemon.json" ]]; then
    echo "需要 sudo 权限来写入系统配置文件"
    sudo cp "$TMP_FILE" "$DAEMON_JSON"
    sudo chmod 644 "$DAEMON_JSON"
else
    # macOS: 直接写入用户目录
    cp "$TMP_FILE" "$DAEMON_JSON"
    chmod 644 "$DAEMON_JSON"
fi

rm -f "$TMP_FILE"

echo ""
echo "✅ Docker 镜像加速器配置完成！"
echo ""
echo "配置文件位置: $DAEMON_JSON"
echo "配置的镜像加速器:"
for mirror in "${MIRRORS[@]}"; do
    echo "  - $mirror"
done
echo ""
echo "⚠️  请重启 Docker Desktop 以使配置生效:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  1. 打开 Docker Desktop"
    echo "  2. 点击菜单栏的 Docker 图标"
    echo "  3. 选择 'Restart' 或 'Quit Docker Desktop' 然后重新启动"
    echo ""
    echo "或者运行以下命令重启:"
    echo "  osascript -e 'quit app \"Docker\"' && sleep 2 && open -a Docker"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "  sudo systemctl restart docker"
    echo "  或"
    echo "  sudo service docker restart"
fi
echo ""
echo "验证配置是否生效:"
echo "  docker info | grep -A 10 'Registry Mirrors'"
