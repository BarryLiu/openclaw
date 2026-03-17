# OpenClaw File Manager Plugin

## 概述

这是一个功能完整的 OpenClaw 插件，提供以下核心功能：

- **文件管理**：上传/下载/列表/删除 Agent 工作空间文件
- **文件夹上传**：支持浏览器端选择文件夹批量上传
- **Skill 管理**：安装/卸载/列出 OpenClaw skills
- **插件自更新**：通过浏览器一键更新插件代码
- **插件安装**：支持安装新插件到 OpenClaw
- **配置验证**：自动验证插件配置防止 OpenClaw 崩溃
- **自动备份**：更新前自动备份当前版本

## 部署步骤

### 1. 将插件复制到 OpenClaw 服务器

```bash
# 将 file-manager-plugin 目录复制到 OpenClaw 服务器
scp -r file-manager-plugin root@172.16.10.107:/tmp/

# SSH 到 OpenClaw 服务器
ssh root@172.16.10.107

# 复制到 OpenClaw 容器
docker cp /tmp/file-manager-plugin openclaw:/app/extensions/file-manager
```

### 2. 在 OpenClaw 配置中启用插件

```bash
# 进入 OpenClaw 容器
docker exec -it openclaw bash

# 编辑配置文件
vi /root/.openclaw/config.yaml
```

添加插件配置：

```yaml
plugins:
  installs:
    - file-manager  # 添加这一行
```

### 3. 重启 OpenClaw

```bash
docker restart openclaw
```

### 4. 验证插件已加载

查看 OpenClaw 日志：

```bash
docker logs openclaw | grep "File Manager"
```

应该看到：`File Manager plugin registered`

## API 接口

插件提供以下 HTTP 端点（需要 Gateway Token 认证）：

### 文件管理

#### 上传单个文件
```http
POST /plugins/file-manager/upload
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "agentId": "main",
  "path": "test.txt",
  "content": "base64_encoded_content"
}
```

响应：
```json
{
  "success": true,
  "filename": "test.txt",
  "size": 1024,
  "agentId": "main"
}
```

#### 上传文件夹（批量上传）
```http
POST /plugins/file-manager/upload-folder
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "agentId": "main",
  "files": [
    {
      "path": "folder/file1.txt",
      "content": "base64_encoded_content"
    },
    {
      "path": "folder/file2.txt",
      "content": "base64_encoded_content"
    }
  ]
}
```

响应：
```json
{
  "success": true,
  "agentId": "main",
  "uploaded": 2,
  "failed": 0,
  "results": [
    { "path": "folder/file1.txt", "size": 1024, "success": true },
    { "path": "folder/file2.txt", "size": 2048, "success": true }
  ]
}
```

#### 列出文件
```http
GET /plugins/file-manager/list?agentId=main
Authorization: Bearer YOUR_GATEWAY_TOKEN
```

响应：
```json
{
  "files": [
    {
      "name": "test.txt",
      "path": "/home/node/.openclaw/agents/main/workspace/test.txt",
      "size": 1024,
      "updatedAtMs": 1710489600000,
      "missing": false
    }
  ],
  "workspace": "/home/node/.openclaw/agents/main/workspace"
}
```

#### 下载文件
```http
GET /plugins/file-manager/download?agentId=main&path=test.txt
Authorization: Bearer YOUR_GATEWAY_TOKEN
```

响应：
```json
{
  "content": "base64_encoded_content",
  "filename": "test.txt"
}
```

#### 删除文件
```http
POST /plugins/file-manager/delete
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "agentId": "main",
  "path": "test.txt"
}
```

响应：
```json
{
  "success": true
}
```

### Skill 管理

#### 安装 Skill
```http
POST /plugins/file-manager/skills/install
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "skillId": "skill-id",
  "title": "skill-name",
  "skillFileUrl": "https://example.com/skill.zip"
}
```

响应：
```json
{
  "ok": true,
  "message": "Skill installed successfully",
  "skillPath": "/home/node/.openclaw/skills/skill-name"
}
```

#### 卸载 Skill
```http
POST /plugins/file-manager/skills/uninstall
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "title": "skill-name"
}
```

响应：
```json
{
  "ok": true,
  "message": "Skill uninstalled successfully"
}
```

#### 列出已安装的 Skill
```http
GET /plugins/file-manager/skills/list
Authorization: Bearer YOUR_GATEWAY_TOKEN
```

响应：
```json
{
  "skills": [
    {
      "name": "skill-name",
      "path": "/home/node/.openclaw/skills/skill-name"
    }
  ]
}
```

### 插件管理

#### 查询插件版本
```http
GET /plugins/file-manager/version
Authorization: Bearer YOUR_GATEWAY_TOKEN
```

响应：
```json
{
  "id": "file-manager",
  "name": "File Manager",
  "version": "1.0.0",
  "description": "File upload/download/management for agent workspaces and skills",
  "author": "Your Name"
}
```

#### 更新插件（自更新）
```http
POST /plugins/file-manager/update
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "files": [
    {
      "path": "index.ts",
      "content": "base64_encoded_content"
    },
    {
      "path": "openclaw.plugin.json",
      "content": "base64_encoded_content"
    }
  ]
}
```

响应：
```json
{
  "ok": true,
  "message": "Plugin updated (10 files), OpenClaw will restart",
  "backup": "/app/extensions/file-manager.backup.1710489600000"
}
```

**注意**：
- 更新会自动过滤 `node_modules/`, `.git/`, `dist/` 目录
- 更新前会自动创建备份
- 更新后会触发 OpenClaw 重启（延迟 1 秒）
- 必须包含有效的 `openclaw.plugin.json` 文件

#### 安装新插件
```http
POST /plugins/file-manager/install
Authorization: Bearer YOUR_GATEWAY_TOKEN
Content-Type: application/json

{
  "pluginName": "new-plugin",
  "files": [
    {
      "path": "index.ts",
      "content": "base64_encoded_content"
    },
    {
      "path": "openclaw.plugin.json",
      "content": "base64_encoded_content"
    }
  ]
}
```

响应：
```json
{
  "ok": true,
  "message": "Plugin new-plugin installed (10 files), OpenClaw will restart",
  "pluginDir": "/app/extensions/new-plugin",
  "version": "1.0.0"
}
```

**注意**：
- 如果插件已存在会返回错误，需要使用 update 接口
- 会验证 `manifest.id` 与 `pluginName` 是否匹配
- 安装后会触发 OpenClaw 重启

## openclaw-web 集成

### 前端组件示例

在 openclaw-web 中使用插件功能：

```typescript
const GATEWAY_URL = 'http://172.16.10.107:18947';
const GATEWAY_TOKEN = process.env.VITE_GATEWAY_TOKEN;

// 上传单个文件
async function uploadFile(agentId: string, file: File) {
  const base64 = await fileToBase64(file);

  const response = await fetch(`${GATEWAY_URL}/plugins/file-manager/upload`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      agentId,
      path: file.name,
      content: base64,
    }),
  });

  return response.json();
}

// 上传文件夹（浏览器端选择）
async function uploadFolder(agentId: string) {
  // 使用 webkitdirectory 属性让用户选择文件夹
  const input = document.createElement('input');
  input.type = 'file';
  input.webkitdirectory = true;

  input.onchange = async (e) => {
    const files = Array.from(e.target.files);
    const fileData = await Promise.all(
      files.map(async (file) => ({
        path: file.webkitRelativePath,
        content: await fileToBase64(file),
      }))
    );

    const response = await fetch(`${GATEWAY_URL}/plugins/file-manager/upload-folder`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GATEWAY_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ agentId, files: fileData }),
    });

    return response.json();
  };

  input.click();
}

// 列出文件
async function listFiles(agentId: string) {
  const response = await fetch(
    `${GATEWAY_URL}/plugins/file-manager/list?agentId=${agentId}`,
    {
      headers: {
        'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      },
    }
  );

  return response.json();
}

// 下载文件
async function downloadFile(agentId: string, filename: string) {
  const response = await fetch(
    `${GATEWAY_URL}/plugins/file-manager/download?agentId=${agentId}&path=${encodeURIComponent(filename)}`,
    {
      headers: {
        'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      },
    }
  );

  const data = await response.json();

  // 将 base64 转换为 Blob 并下载
  const blob = base64ToBlob(data.content);
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

// 删除文件
async function deleteFile(agentId: string, filename: string) {
  const response = await fetch(`${GATEWAY_URL}/plugins/file-manager/delete`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ agentId, path: filename }),
  });

  return response.json();
}

// 工具函数
function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const base64 = reader.result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

function base64ToBlob(base64: string): Blob {
  const byteString = atob(base64);
  const ab = new ArrayBuffer(byteString.length);
  const ia = new Uint8Array(ab);
  for (let i = 0; i < byteString.length; i++) {
    ia[i] = byteString.charCodeAt(i);
  }
  return new Blob([ab]);
}
```

### 插件自更新功能

```typescript
// 查询插件版本
async function getPluginVersion() {
  const response = await fetch(`${GATEWAY_URL}/plugins/file-manager/version`, {
    headers: {
      'Authorization': `Bearer ${GATEWAY_TOKEN}`,
    },
  });

  return response.json();
}

// 一键更新插件（从本地文件夹）
async function updatePlugin() {
  // 让用户选择插件文件夹
  const input = document.createElement('input');
  input.type = 'file';
  input.webkitdirectory = true;

  input.onchange = async (e) => {
    const files = Array.from(e.target.files);

    // 收集所有文件
    const fileData = await Promise.all(
      files.map(async (file) => ({
        path: file.webkitRelativePath.split('/').slice(1).join('/'), // 移除根文件夹名
        content: await fileToBase64(file),
      }))
    );

    // 调用更新接口
    const response = await fetch(`${GATEWAY_URL}/plugins/file-manager/update`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GATEWAY_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ files: fileData }),
    });

    const result = await response.json();

    if (result.ok) {
      alert(`插件更新成功！备份位置：${result.backup}`);
      // OpenClaw 会在 1 秒后自动重启
    }
  };

  input.click();
}
```

### 后端代理示例

如果需要从服务器端更新插件（例如从本地路径读取）：

```typescript
// server/routes/plugins.ts
import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';

const router = express.Router();

router.post('/update', async (req, res) => {
  try {
    const { pluginName } = req.body;

    // 从环境变量读取插件路径
    const pluginPath = process.env[`PLUGIN_PATH_${pluginName.toUpperCase().replace(/-/g, '_')}`];

    if (!pluginPath) {
      return res.status(400).json({ error: 'Plugin path not configured' });
    }

    // 递归收集文件
    const files = await collectFiles(pluginPath, pluginPath);

    // 调用 Gateway 的更新接口
    const response = await fetch(`${GATEWAY_URL}/plugins/${pluginName}/update`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GATEWAY_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ files }),
    });

    const result = await response.json();
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

async function collectFiles(dir: string, baseDir: string) {
  const files = [];
  const entries = await fs.readdir(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    // 跳过不需要的目录
    if (entry.name === 'node_modules' || entry.name === '.git') {
      continue;
    }

    if (entry.isDirectory()) {
      const subFiles = await collectFiles(fullPath, baseDir);
      files.push(...subFiles);
    } else if (entry.isFile()) {
      const content = await fs.readFile(fullPath);
      const relativePath = path.relative(baseDir, fullPath);
      files.push({
        path: relativePath.replace(/\\/g, '/'),
        content: content.toString('base64'),
      });
    }
  }

  return files;
}

export default router;
```

## 故障排查

### 插件未加载

1. 检查插件目录是否正确：
```bash
docker exec openclaw ls -la /app/extensions/file-manager
```

应该看到 `index.js`, `openclaw.plugin.json` 等文件。

2. 检查配置文件：
```bash
docker exec openclaw cat /root/.openclaw/config.yaml | grep file-manager
```

应该在 `plugins.installs` 中看到 `file-manager`。

3. 查看错误日志：
```bash
docker logs openclaw --tail 100
```

查找包含 "File Manager" 或 "file-manager" 的日志。

### 配置验证失败

如果看到类似错误：
```
[file-manager] Invalid config: maxFileSize must be a number
```

检查 `config.yaml` 中的配置类型是否正确：
- `maxFileSize` 必须是数字，不能是字符串
- `allowedExtensions` 必须是数组

### API 调用失败

1. **401 Unauthorized**
   - 检查 Gateway Token 是否正确
   - 确认请求头中包含 `Authorization: Bearer YOUR_TOKEN`

2. **404 Not Found**
   - 确认插件已正确加载
   - 检查 URL 路径是否正确（必须以 `/plugins/file-manager` 开头）

3. **413 File Too Large**
   - 文件超过 `maxFileSize` 限制
   - 调整配置或分割文件

4. **400 Bad Request**
   - 检查请求体格式是否正确
   - 确认必需字段都已提供（如 `agentId`, `path`, `content`）

### 插件更新失败

1. **Missing openclaw.plugin.json**
   - 确保上传的文件中包含 `openclaw.plugin.json`
   - 检查文件路径是否正确

2. **Invalid manifest**
   - 检查 manifest 中的必需字段：`id`, `name`, `version`, `main`
   - 确认 JSON 格式正确

3. **Main file not found**
   - 确保 `main` 字段指定的文件存在于上传的文件中
   - 检查文件路径大小写

4. **更新后 OpenClaw 未重启**
   - 检查容器日志：`docker logs openclaw`
   - 手动重启：`docker restart openclaw`

### 文件上传失败

1. **Access denied**
   - 文件路径包含 `..` 等不安全字符
   - 尝试访问工作空间外的路径

2. **Workspace not found**
   - Agent ID 不存在
   - 工作空间路径配置错误
   - 检查环境变量 `OPENCLAW_HOME` 或 `OPENCLAW_DATA_DIR`

### 查看详细日志

启用调试日志：
```bash
docker exec openclaw sh -c 'export DEBUG=openclaw:* && node /app/dist/index.js'
```

## 配置选项

插件支持以下配置参数（在 `config.yaml` 中配置）：

```yaml
plugins:
  installs:
    - file-manager
  config:
    file-manager:
      maxFileSize: 104857600  # 最大文件大小（字节），默认 100MB
      allowedExtensions:      # 允许的文件扩展名（可选）
        - .txt
        - .pdf
        - .jpg
        - .png
        - .zip
```

### 配置验证

插件会在启动时自动验证配置：
- `maxFileSize` 必须是数字类型
- `allowedExtensions` 必须是字符串数组
- 如果配置无效，插件会拒绝加载并记录错误日志

### openclaw.plugin.json 必需字段

插件的 manifest 文件必须包含以下字段：

```json
{
  "id": "plugin-id",           // 插件唯一标识
  "name": "Plugin Name",       // 插件名称
  "version": "1.0.0",          // 版本号
  "description": "...",        // 描述
  "author": "Your Name",       // 作者
  "main": "index.js"           // 入口文件
}
```

更新或安装插件时会自动验证这些字段，如果缺失或类型错误会返回 400 错误。

## 安全建议

1. **Token 安全**
   - 不要在前端代码中硬编码 Gateway Token
   - 使用环境变量存储敏感信息
   - 定期轮换 Token

2. **文件大小限制**
   - 设置合理的 `maxFileSize` 防止资源耗尽
   - 建议不超过 100MB

3. **文件类型验证**
   - 使用 `allowedExtensions` 限制允许的文件类型
   - 在服务端验证文件内容，不要只依赖扩展名

4. **路径安全**
   - 插件会自动验证文件路径，防止目录遍历攻击
   - 不要禁用路径验证

5. **定期清理**
   - 定期清理临时文件和备份
   - 监控磁盘使用情况

6. **备份管理**
   - 插件更新会自动创建备份（格式：`plugin-name.backup.timestamp`）
   - 定期清理旧备份以节省空间
   - 重要更新前手动创建额外备份

## 开发指南

### 项目结构

```
file-manager/
├── index.ts                 # 插件入口
├── openclaw.plugin.json     # 插件配置
├── src/
│   ├── http.ts             # 文件管理 HTTP 处理器
│   ├── skills.ts           # Skill 管理处理器
│   └── update.ts           # 插件更新/安装处理器
├── package.json
└── README.md
```

### 本地开发

1. 安装依赖：
```bash
pnpm install
```

2. 构建插件：
```bash
pnpm build
```

3. 部署到 OpenClaw：
```bash
# 复制到服务器
scp -r dist/* root@172.16.10.107:/tmp/file-manager/

# 复制到容器
docker cp /tmp/file-manager openclaw:/app/extensions/file-manager

# 重启 OpenClaw
docker restart openclaw
```

### 添加新功能

1. 在 `src/` 目录下创建新的处理器文件
2. 在 `index.ts` 中注册新的路由
3. 更新 `openclaw.plugin.json` 的版本号
4. 构建并部署

示例：
```typescript
// src/new-feature.ts
export function createNewFeatureHandler(params: { logger: any }) {
  return async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
    const url = new URL(req.url || "/", "http://localhost");

    if (url.pathname === "/plugins/file-manager/new-feature") {
      // 处理逻辑
      sendJson(res, 200, { ok: true });
      return true;
    }

    return false;
  };
}

// index.ts
import { createNewFeatureHandler } from "./src/new-feature.js";

const plugin = {
  register(api: OpenClawPluginApi) {
    api.registerHttpRoute({
      path: "/plugins/file-manager",
      auth: "gateway",
      match: "prefix",
      handler: async (req, res) => {
        const newFeatureHandler = createNewFeatureHandler({ logger: api.logger });
        return (await newFeatureHandler(req, res)) || /* 其他处理器 */;
      },
    });
  },
};
```

### 测试

使用 curl 测试 API：

```bash
# 测试版本查询
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://172.16.10.107:18947/plugins/file-manager/version

# 测试文件上传
curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"agentId":"main","path":"test.txt","content":"SGVsbG8gV29ybGQ="}' \
  http://172.16.10.107:18947/plugins/file-manager/upload

# 测试文件列表
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://172.16.10.107:18947/plugins/file-manager/list?agentId=main"
```

## 版本历史

### v1.0.0
- 初始版本
- 文件上传/下载/列表/删除
- Skill 安装/卸载/列表
- 插件自更新功能
- 插件安装功能
- 配置验证
- 自动备份

## 许可证

MIT

## 作者

Your Name

## 贡献

欢迎提交 Issue 和 Pull Request！
