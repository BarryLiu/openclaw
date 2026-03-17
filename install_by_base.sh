#!/usr/bin/env bash
set -euo pipefail

# 脚本说明：安装已编译好的 openclaw Docker 镜像容器
# 用法: ./install_by_base.sh <名称> <OPENCLAW_GATEWAY_TOKEN> <OPENCLAW_GATEWAY_PORT> <OPENCLAW_BRIDGE_PORT>
# 举例: ./install_by_base.sh my-instance 58b9ff0efdf105b964fba2b296c59766f6e47dbfb3989f059d057225de2a64b3 18891 18892

# 参数检查
if [[ $# -ne 4 ]]; then
  echo "错误: 需要提供四个参数" >&2
  echo "用法: $0 <名称> <OPENCLAW_GATEWAY_TOKEN> <OPENCLAW_GATEWAY_PORT> <OPENCLAW_BRIDGE_PORT>" >&2
  exit 1
fi

OPENCLAW_NAME="$1"
OPENCLAW_GATEWAY_TOKEN="$2"
OPENCLAW_GATEWAY_PORT="$3"
OPENCLAW_BRIDGE_PORT="$4"

# 验证参数非空
if [[ -z "$OPENCLAW_NAME" ]]; then
  echo "错误: 名称 不能为空" >&2
  exit 1
fi

# 验证名称格式（Docker 容器名称只能包含字母、数字、下划线、连字符和点）
if ! [[ "$OPENCLAW_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
  echo "错误: 名称只能包含字母、数字、下划线、连字符和点" >&2
  exit 1
fi

if [[ -z "$OPENCLAW_GATEWAY_TOKEN" ]]; then
  echo "错误: OPENCLAW_GATEWAY_TOKEN 不能为空" >&2
  exit 1
fi

if [[ -z "$OPENCLAW_GATEWAY_PORT" ]]; then
  echo "错误: OPENCLAW_GATEWAY_PORT 不能为空" >&2
  exit 1
fi

if [[ -z "$OPENCLAW_BRIDGE_PORT" ]]; then
  echo "错误: OPENCLAW_BRIDGE_PORT 不能为空" >&2
  exit 1
fi

# 验证端口号是否为有效数字
if ! [[ "$OPENCLAW_GATEWAY_PORT" =~ ^[0-9]+$ ]] || [[ "$OPENCLAW_GATEWAY_PORT" -lt 1 ]] || [[ "$OPENCLAW_GATEWAY_PORT" -gt 65535 ]]; then
  echo "错误: OPENCLAW_GATEWAY_PORT 必须是 1-65535 之间的有效端口号" >&2
  exit 1
fi

if ! [[ "$OPENCLAW_BRIDGE_PORT" =~ ^[0-9]+$ ]] || [[ "$OPENCLAW_BRIDGE_PORT" -lt 1 ]] || [[ "$OPENCLAW_BRIDGE_PORT" -gt 65535 ]]; then
  echo "错误: OPENCLAW_BRIDGE_PORT 必须是 1-65535 之间的有效端口号" >&2
  exit 1
fi

# 检查端口是否被占用
check_port_in_use() {
  local port="$1"
  local port_name="$2"
  
  # 优先使用 ss 命令（现代 Linux 系统）
  if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -q ":${port} "; then
      echo "错误: 端口 ${port} (${port_name}) 已被占用" >&2
      echo "提示: 使用 'ss -tuln | grep :${port}' 查看占用该端口的进程" >&2
      return 1
    fi
  # 备选使用 netstat 命令
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
      echo "错误: 端口 ${port} (${port_name}) 已被占用" >&2
      echo "提示: 使用 'netstat -tuln | grep :${port}' 查看占用该端口的进程" >&2
      return 1
    fi
  # 最后尝试使用 lsof 命令
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -i ":${port}" >/dev/null 2>&1; then
      echo "错误: 端口 ${port} (${port_name}) 已被占用" >&2
      echo "提示: 使用 'lsof -i :${port}' 查看占用该端口的进程" >&2
      return 1
    fi
  else
    echo "警告: 无法检查端口占用情况（未找到 ss/netstat/lsof 命令）" >&2
    echo "警告: 如果端口被占用，后续操作可能会失败" >&2
  fi
  
  return 0
}

# 检查两个端口是否被占用
if ! check_port_in_use "$OPENCLAW_GATEWAY_PORT" "OPENCLAW_GATEWAY_PORT"; then
  exit 1
fi

if ! check_port_in_use "$OPENCLAW_BRIDGE_PORT" "OPENCLAW_BRIDGE_PORT"; then
  exit 1
fi

# 获取脚本所在目录
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查 docker 和 docker compose 是否可用
if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令" >&2
  exit 1
fi

# 检测 docker compose 命令（兼容新旧版本）
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1 && docker-compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  echo "错误: Docker Compose 不可用" >&2
  exit 1
fi

# 导出环境变量供后续使用
export OPENCLAW_NAME
export OPENCLAW_GATEWAY_TOKEN
export OPENCLAW_GATEWAY_PORT
export OPENCLAW_BRIDGE_PORT

echo "==> 参数验证通过"
echo "名称: $OPENCLAW_NAME"
echo "Gateway Token: $OPENCLAW_GATEWAY_TOKEN"
echo "Gateway Port: $OPENCLAW_GATEWAY_PORT"
echo "Bridge Port: $OPENCLAW_BRIDGE_PORT"
echo ""

# ============================================
# 执行逻辑
# ============================================

# 1. 复制文件夹
BASE_FOLDER="xcopenclaw-base"
TARGET_FOLDER="xc-openclaw-${OPENCLAW_NAME}"

if [[ ! -d "$BASE_FOLDER" ]]; then
  echo "错误: 找不到基础文件夹: $BASE_FOLDER" >&2
  exit 1
fi

# 检查基础文件夹中是否有 docker-compose.yml
if [[ ! -f "$BASE_FOLDER/docker-compose.yml" ]]; then
  echo "错误: 基础文件夹中找不到 docker-compose.yml 文件: $BASE_FOLDER/docker-compose.yml" >&2
  exit 1
fi

if [[ -d "$TARGET_FOLDER" ]]; then
  echo "错误: 目标文件夹已存在: $TARGET_FOLDER" >&2
  exit 1
fi

echo "==> 步骤 1: 复制文件夹"
echo "从 $BASE_FOLDER 复制到 $TARGET_FOLDER"
cp -r "$BASE_FOLDER" "$TARGET_FOLDER"
echo "✅ 文件夹复制完成"

# 进入目标文件夹
cd "$TARGET_FOLDER"

# 2. 设置 .openclaw 文件夹权限
if [[ -d ".openclaw" ]]; then
  echo ""
  echo "==> 步骤 2: 设置 .openclaw 文件夹权限"
  chmod -R 777 .openclaw
  echo "✅ 权限设置完成"
else
  echo "警告: 未找到 .openclaw 文件夹，跳过权限设置"
fi

# 3. 修改 .env 文件
ENV_FILE=".env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "错误: 找不到 .env 文件: $ENV_FILE" >&2
  exit 1
fi

echo ""
echo "==> 步骤 3: 修改 .env 文件"

# 使用 sed 修改 .env 文件中的变量
# 如果变量存在则替换，如果不存在则追加
update_env_var() {
  local file="$1"
  local var_name="$2"
  local var_value="$3"
  
  # 转义特殊字符
  local escaped_value="${var_value//\//\\/}"
  escaped_value="${escaped_value//&/\\&}"
  
  if grep -q "^${var_name}=" "$file" 2>/dev/null; then
    # 变量存在，替换值
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS 使用不同的 sed 语法
      sed -i '' "s|^${var_name}=.*|${var_name}=${escaped_value}|" "$file"
    else
      # Linux 使用标准 sed 语法
      sed -i "s|^${var_name}=.*|${var_name}=${escaped_value}|" "$file"
    fi
  else
    # 变量不存在，追加到文件末尾
    echo "${var_name}=${var_value}" >> "$file"
  fi
}

update_env_var "$ENV_FILE" "OPENCLAW_GATEWAY_TOKEN" "$OPENCLAW_GATEWAY_TOKEN"
update_env_var "$ENV_FILE" "OPENCLAW_GATEWAY_PORT" "$OPENCLAW_GATEWAY_PORT"
update_env_var "$ENV_FILE" "OPENCLAW_BRIDGE_PORT" "$OPENCLAW_BRIDGE_PORT"

echo "✅ .env 文件修改完成"

# 4. 启动 docker-compose（仅启动 openclaw-gateway 服务）
echo ""
echo "==> 步骤 4: 启动 Docker Compose (openclaw-gateway)"
$DOCKER_COMPOSE_CMD up -d openclaw-gateway
if [[ $? -eq 0 ]]; then
  echo "✅ Docker Compose 启动成功"
else
  echo "错误: Docker Compose 启动失败" >&2
  exit 1
fi

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 5. 修改 openclaw.json 添加 allowedOrigins
# OPENCLAW_JSON=".openclaw/openclaw.json"
# if [[ ! -f "$OPENCLAW_JSON" ]]; then
#   echo "警告: 找不到 openclaw.json 文件: $OPENCLAW_JSON，跳过 allowedOrigins 配置"
# else
#   echo ""
#   echo "==> 步骤 5: 配置 allowedOrigins"
#   
#   # 获取本机 IP 地址
#   get_local_ip() {
#     # 优先使用 ip 命令（Linux）
#     if command -v ip >/dev/null 2>&1; then
#       # 尝试使用 -P 选项（GNU grep）
#       ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' 2>/dev/null | head -1 || \
#       ip route get 8.8.8.8 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}' | head -1
#     # 备选使用 hostname 命令（Linux）
#     elif command -v hostname >/dev/null 2>&1 && [[ "$(uname)" != "Darwin" ]]; then
#       hostname -I 2>/dev/null | awk '{print $1}'
#     # macOS 使用 ifconfig
#     elif command -v ifconfig >/dev/null 2>&1; then
#       if [[ "$(uname)" == "Darwin" ]]; then
#         # macOS
#         ifconfig | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1
#       else
#         # Linux
#         ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1
#       fi
#     else
#       echo "127.0.0.1"
#     fi
#   }
#   
#   LOCAL_IP="$(get_local_ip)"
#   if [[ -z "$LOCAL_IP" ]]; then
#     LOCAL_IP="127.0.0.1"
#   fi
#   
#   ALLOWED_ORIGIN="http://${LOCAL_IP}:${OPENCLAW_GATEWAY_PORT}"
#   echo "添加允许的来源: $ALLOWED_ORIGIN"
#   
#   # 使用 Python 或 Node.js 来修改 JSON 文件
#   if command -v python3 >/dev/null 2>&1; then
#     python3 <<PYTHON_SCRIPT
# import json
# import sys
# 
# json_file = "$OPENCLAW_JSON"
# origin = "$ALLOWED_ORIGIN"
# 
# try:
#     with open(json_file, 'r', encoding='utf-8') as f:
#         config = json.load(f)
#     
#     # 确保 gateway 和 controlUi 存在
#     if 'gateway' not in config:
#         config['gateway'] = {}
#     if 'controlUi' not in config['gateway']:
#         config['gateway']['controlUi'] = {}
#     if 'allowedOrigins' not in config['gateway']['controlUi']:
#         config['gateway']['controlUi']['allowedOrigins'] = []
#     
#     # 检查是否已存在
#     origins = config['gateway']['controlUi']['allowedOrigins']
#     if origin not in origins:
#         origins.append(origin)
#         config['gateway']['controlUi']['allowedOrigins'] = origins
#         
#         # 写回文件
#         with open(json_file, 'w', encoding='utf-8') as f:
#             json.dump(config, f, indent=2, ensure_ascii=False)
#         print("✅ allowedOrigins 配置成功")
#     else:
#         print("ℹ️  allowedOrigins 已包含该来源")
# except Exception as e:
#     print(f"错误: 修改 JSON 文件失败: {e}", file=sys.stderr)
#     sys.exit(1)
# PYTHON_SCRIPT
#   elif command -v node >/dev/null 2>&1; then
#     node <<NODE_SCRIPT
# const fs = require('fs');
# const jsonFile = "$OPENCLAW_JSON";
# const origin = "$ALLOWED_ORIGIN";
# 
# try {
#     const config = JSON.parse(fs.readFileSync(jsonFile, 'utf8'));
#     
#     // 确保 gateway 和 controlUi 存在
#     if (!config.gateway) config.gateway = {};
#     if (!config.gateway.controlUi) config.gateway.controlUi = {};
#     if (!Array.isArray(config.gateway.controlUi.allowedOrigins)) {
#         config.gateway.controlUi.allowedOrigins = [];
#     }
#     
#     // 检查是否已存在
#     const origins = config.gateway.controlUi.allowedOrigins;
#     if (!origins.includes(origin)) {
#         origins.push(origin);
#         config.gateway.controlUi.allowedOrigins = origins;
#         
#         // 写回文件
#         fs.writeFileSync(jsonFile, JSON.stringify(config, null, 2), 'utf8');
#         console.log("✅ allowedOrigins 配置成功");
#     } else {
#         console.log("ℹ️  allowedOrigins 已包含该来源");
#     }
# } catch (e) {
#     console.error("错误: 修改 JSON 文件失败:", e.message);
#     process.exit(1);
# }
# NODE_SCRIPT
#   else
#     echo "警告: 未找到 python3 或 node，无法修改 JSON 文件"
#   fi
# fi

# 6. 执行设备批准命令（需要先启动 openclaw-cli 服务）
echo ""
echo "==> 步骤 6: 批准设备配对请求"

# 检查 gateway 服务是否运行
GATEWAY_SERVICE="openclaw-gateway"
CLI_SERVICE="openclaw-cli"

# 等待 gateway 服务完全启动
echo "等待 gateway 服务启动..."
for i in {1..30}; do
  if $DOCKER_COMPOSE_CMD ps "$GATEWAY_SERVICE" | grep -q "Up"; then
    break
  fi
  sleep 1
done

if $DOCKER_COMPOSE_CMD ps "$GATEWAY_SERVICE" | grep -q "Up"; then
  echo "临时启动 openclaw-cli 服务以执行设备批准命令..."
  # 临时启动 cli 服务来执行命令
  $DOCKER_COMPOSE_CMD up -d "$CLI_SERVICE" >/dev/null 2>&1
  sleep 2
  
  echo "执行设备批准命令..."
  # 尝试执行设备批准命令
  if $DOCKER_COMPOSE_CMD exec -T "$CLI_SERVICE" openclaw devices approve --latest 2>/dev/null; then
    echo "✅ 设备批准成功"
  elif $DOCKER_COMPOSE_CMD exec -T "$CLI_SERVICE" openclaw devices approve 2>/dev/null; then
    echo "✅ 设备批准成功"
  else
    echo "ℹ️  当前没有待批准的设备配对请求"
  fi
  
  # 停止 cli 服务（只保留 gateway 服务运行）
  echo "停止 openclaw-cli 服务..."
  $DOCKER_COMPOSE_CMD stop "$CLI_SERVICE" >/dev/null 2>&1
else
  echo "警告: $GATEWAY_SERVICE 服务未运行，跳过设备批准步骤"
fi

echo ""
echo "==> 安装完成！"
echo "实例名称: $OPENCLAW_NAME"
echo "Gateway Port: $OPENCLAW_GATEWAY_PORT"
echo "Bridge Port: $OPENCLAW_BRIDGE_PORT"
echo "配置文件位置: $(pwd)/.openclaw/openclaw.json"
echo ""
echo "界面访问地址:"
echo "  http://172.16.10.107:${OPENCLAW_GATEWAY_PORT}/#token=${OPENCLAW_GATEWAY_TOKEN}"
echo ""
echo "常用命令:"
echo "  查看日志: cd $TARGET_FOLDER && $DOCKER_COMPOSE_CMD logs -f"
echo "  停止服务: cd $TARGET_FOLDER && $DOCKER_COMPOSE_CMD down"
echo "  重启服务: cd $TARGET_FOLDER && $DOCKER_COMPOSE_CMD restart"
