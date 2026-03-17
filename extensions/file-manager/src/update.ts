import type { IncomingMessage, ServerResponse } from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";

export function createPluginUpdateHttpHandler(params: { logger: any }) {
  const { logger } = params;

  return async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
    const url = new URL(req.url || "/", "http://localhost");
    const pathname = url.pathname;

    if (pathname === "/plugins/file-manager/update") {
      return handleUpdate(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/version") {
      return handleVersion(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/install") {
      return handleInstall(req, res, { logger });
    }

    return false;
  };
}

async function handleVersion(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "GET") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const pluginDir = path.resolve(__dirname, "..");
    const manifestPath = path.join(pluginDir, "openclaw.plugin.json");
    const manifest = JSON.parse(await fs.readFile(manifestPath, "utf-8"));

    sendJson(res, 200, {
      id: manifest.id,
      name: manifest.name,
      version: manifest.version,
      description: manifest.description,
      author: manifest.author,
    });
  } catch (error: any) {
    ctx.logger.error("[plugin-version] Failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleUpdate(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { files } = await readJsonBody(req);

    if (!Array.isArray(files) || files.length === 0) {
      sendJson(res, 400, { error: "Missing files array" });
      return true;
    }

    // 过滤掉不需要的文件
    const filteredFiles = files.filter((file: any) => {
      const filePath = file.path || "";
      // 跳过 node_modules, .git, dist 等目录
      if (filePath.includes("node_modules/") ||
          filePath.includes(".git/") ||
          filePath.includes("dist/") ||
          filePath.startsWith("node_modules") ||
          filePath.startsWith(".git") ||
          filePath.startsWith("dist")) {
        return false;
      }
      return true;
    });

    ctx.logger.info(`[plugin-update] Filtered ${files.length} files to ${filteredFiles.length} files`);

    // 验证插件配置文件
    const manifestFile = filteredFiles.find((f: any) =>
      f.path.endsWith("openclaw.plugin.json") || f.path === "openclaw.plugin.json"
    );

    if (!manifestFile) {
      sendJson(res, 400, { error: "Missing openclaw.plugin.json file" });
      return true;
    }

    // 验证 manifest 格式
    try {
      const manifestContent = Buffer.from(manifestFile.content, "base64").toString("utf-8");
      const manifest = JSON.parse(manifestContent);

      // 必需字段验证
      if (!manifest.id || typeof manifest.id !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'id' field" });
        return true;
      }

      if (!manifest.name || typeof manifest.name !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'name' field" });
        return true;
      }

      if (!manifest.version || typeof manifest.version !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'version' field" });
        return true;
      }

      if (!manifest.main || typeof manifest.main !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'main' field" });
        return true;
      }

      // 验证 main 文件是否存在
      const mainFile = filteredFiles.find((f: any) =>
        f.path.endsWith(manifest.main) || f.path === manifest.main
      );

      if (!mainFile) {
        sendJson(res, 400, { error: `Invalid manifest: main file '${manifest.main}' not found in uploaded files` });
        return true;
      }

      ctx.logger.info(`[plugin-update] Manifest validation passed: ${manifest.id} v${manifest.version}`);
    } catch (error: any) {
      sendJson(res, 400, { error: `Invalid manifest JSON: ${error.message}` });
      return true;
    }

    // 获取插件目录
    const pluginDir = path.resolve(__dirname, "..");
    ctx.logger.info(`[plugin-update] Updating plugin at: ${pluginDir}`);

    // 备份当前插件
    const backupDir = `${pluginDir}.backup.${Date.now()}`;
    await fs.cp(pluginDir, backupDir, { recursive: true });
    ctx.logger.info(`[plugin-update] Backup created at: ${backupDir}`);

    // 写入新文件
    let updatedCount = 0;
    for (const file of filteredFiles) {
      const { path: relativePath, content } = file;

      if (!relativePath || !content) {
        continue;
      }

      const buffer = Buffer.from(content, "base64");
      const fullPath = path.join(pluginDir, relativePath);
      const dir = path.dirname(fullPath);

      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(fullPath, buffer);
      updatedCount++;
      ctx.logger.info(`[plugin-update] Updated: ${relativePath}`);
    }

    ctx.logger.info(`[plugin-update] Updated ${updatedCount} files, triggering restart...`);

    // 发送响应
    sendJson(res, 200, {
      ok: true,
      message: `Plugin updated (${updatedCount} files), OpenClaw will restart`,
      backup: backupDir,
    });

    // 延迟重启，让响应先发送
    setTimeout(async () => {
      try {
        ctx.logger.info("[plugin-update] Triggering OpenClaw restart...");
        await triggerRestart(ctx.logger);
      } catch (error: any) {
        ctx.logger.error("[plugin-update] Restart failed:", error.message);
      }
    }, 1000);
  } catch (error: any) {
    ctx.logger.error("[plugin-update] Update failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleInstall(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { pluginName, files } = await readJsonBody(req);

    if (!pluginName || !Array.isArray(files) || files.length === 0) {
      sendJson(res, 400, { error: "Missing pluginName or files array" });
      return true;
    }

    // 过滤掉不需要的文件
    const filteredFiles = files.filter((file: any) => {
      const filePath = file.path || "";
      if (filePath.includes("node_modules/") ||
          filePath.includes(".git/") ||
          filePath.includes("dist/") ||
          filePath.startsWith("node_modules") ||
          filePath.startsWith(".git") ||
          filePath.startsWith("dist")) {
        return false;
      }
      return true;
    });

    ctx.logger.info(`[plugin-install] Installing plugin: ${pluginName} (${filteredFiles.length} files)`);

    // 验证插件配置文件
    const manifestFile = filteredFiles.find((f: any) =>
      f.path.endsWith("openclaw.plugin.json") || f.path === "openclaw.plugin.json" ||
      f.path.includes("/openclaw.plugin.json")
    );

    if (!manifestFile) {
      sendJson(res, 400, { error: "Missing openclaw.plugin.json file" });
      return true;
    }

    // 验证 manifest 格式
    let manifest: any;
    try {
      const manifestContent = Buffer.from(manifestFile.content, "base64").toString("utf-8");
      manifest = JSON.parse(manifestContent);

      // 必需字段验证
      if (!manifest.id || typeof manifest.id !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'id' field" });
        return true;
      }

      if (!manifest.name || typeof manifest.name !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'name' field" });
        return true;
      }

      if (!manifest.version || typeof manifest.version !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'version' field" });
        return true;
      }

      if (!manifest.main || typeof manifest.main !== "string") {
        sendJson(res, 400, { error: "Invalid manifest: missing or invalid 'main' field" });
        return true;
      }

      // 验证 pluginName 与 manifest.id 是否匹配
      if (manifest.id !== pluginName) {
        sendJson(res, 400, {
          error: `Plugin name mismatch: expected '${pluginName}' but manifest.id is '${manifest.id}'`
        });
        return true;
      }

      // 验证 main 文件是否存在
      const mainFile = filteredFiles.find((f: any) =>
        f.path.endsWith(manifest.main) || f.path === manifest.main || f.path.includes(`/${manifest.main}`)
      );

      if (!mainFile) {
        sendJson(res, 400, { error: `Invalid manifest: main file '${manifest.main}' not found in uploaded files` });
        return true;
      }

      ctx.logger.info(`[plugin-install] Manifest validation passed: ${manifest.id} v${manifest.version}`);
    } catch (error: any) {
      sendJson(res, 400, { error: `Invalid manifest JSON: ${error.message}` });
      return true;
    }

    // 获取插件安装目录
    const extensionsDir = path.resolve("/app/extensions");
    const pluginDir = path.join(extensionsDir, pluginName);

    // 检查插件是否已存在
    try {
      await fs.access(pluginDir);
      sendJson(res, 400, { error: `Plugin ${pluginName} already exists. Use update instead.` });
      return true;
    } catch (e) {
      // 插件不存在，继续安装
    }

    // 创建插件目录
    await fs.mkdir(pluginDir, { recursive: true });

    // 写入文件
    let installedCount = 0;
    for (const file of filteredFiles) {
      const { path: relativePath, content } = file;

      if (!relativePath || !content) {
        continue;
      }

      // 移除文件路径中的插件名前缀（如果有）
      let cleanPath = relativePath;
      if (cleanPath.startsWith(`${pluginName}/`)) {
        cleanPath = cleanPath.substring(pluginName.length + 1);
      }

      const buffer = Buffer.from(content, "base64");
      const fullPath = path.join(pluginDir, cleanPath);
      const dir = path.dirname(fullPath);

      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(fullPath, buffer);
      installedCount++;
      ctx.logger.info(`[plugin-install] Installed: ${cleanPath}`);
    }

    ctx.logger.info(`[plugin-install] Installed ${installedCount} files, triggering restart...`);

    // 发送响应
    sendJson(res, 200, {
      ok: true,
      message: `Plugin ${pluginName} installed (${installedCount} files), OpenClaw will restart`,
      pluginDir,
      version: manifest.version,
    });

    // 延迟重启
    setTimeout(async () => {
      try {
        ctx.logger.info("[plugin-install] Triggering OpenClaw restart...");
        await triggerRestart(ctx.logger);
      } catch (error: any) {
        ctx.logger.error("[plugin-install] Restart failed:", error.message);
      }
    }, 1000);
  } catch (error: any) {
    ctx.logger.error("[plugin-install] Install failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

/**
 * 触发 OpenClaw 重启，按可靠性降级：
 * 1. touch config 文件 → chokidar watcher 检测到变更 → 触发 reload/restart
 * 2. SIGUSR1 信号
 * 3. process.exit → 依赖 Docker restart policy 重启容器
 */
async function triggerRestart(logger: any) {
  // 方式 1：touch config 文件触发 chokidar watcher
  const stateDir = process.env.OPENCLAW_STATE_DIR || path.join(process.env.OPENCLAW_HOME || "/home/node", ".openclaw");
  const configCandidates = [
    process.env.OPENCLAW_CONFIG_PATH,
    path.join(stateDir, "openclaw.json"),
    path.join(stateDir, "clawdbot.json"),
  ].filter(Boolean) as string[];

  for (const configPath of configCandidates) {
    try {
      await fs.access(configPath);
      // touch: 读取内容后原样写回，触发 chokidar change 事件
      const content = await fs.readFile(configPath, "utf-8");
      await fs.writeFile(configPath, content, "utf-8");
      logger.info(`[restart] Touched config file: ${configPath} → should trigger reload`);
      return;
    } catch {
      // 文件不存在，尝试下一个
    }
  }

  // 方式 2：发信号
  logger.warn("[restart] No config file found, trying SIGUSR1...");
  try {
    process.kill(1, "SIGUSR1");
    logger.info("[restart] Sent SIGUSR1 to PID 1");
    return;
  } catch {
    // ignore
  }

  // 方式 3：退出进程，依赖 Docker restart policy
  logger.warn("[restart] Signal failed, falling back to process.exit(0)");
  process.exit(0);
}

async function readJsonBody(req: IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      try {
        resolve(JSON.parse(body));
      } catch (e) {
        reject(e);
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res: ServerResponse, status: number, data: any) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(data));
}
