import type { IncomingMessage, ServerResponse } from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";

export function createFileManagerHttpHandler(params: {
  api: OpenClawPluginApi;
  maxFileSize: number;
  logger: any;
}) {
  const { maxFileSize, logger } = params;

  return async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
    const url = new URL(req.url || "/", "http://localhost");
    const pathname = url.pathname;

    if (pathname === "/plugins/file-manager/upload") {
      return handleUpload(req, res, { maxFileSize, logger });
    }

    if (pathname === "/plugins/file-manager/upload-folder") {
      return handleUploadFolder(req, res, { maxFileSize, logger });
    }

    if (pathname === "/plugins/file-manager/list") {
      return handleList(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/download") {
      return handleDownload(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/delete") {
      return handleDelete(req, res, { logger });
    }

    return false;
  };
}

async function handleUpload(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { agentId, path: filename, content, extract, targetDir } = await readJsonBody(req);

    if (!agentId || !filename || !content) {
      sendJson(res, 400, { error: "Missing required fields" });
      return true;
    }

    const workspacePath = getWorkspacePath(agentId);
    await fs.mkdir(workspacePath, { recursive: true });

    const buffer = Buffer.from(content, "base64");

    if (buffer.length > ctx.maxFileSize) {
      sendJson(res, 413, { error: "File too large" });
      return true;
    }

    // 如果需要解压（文件夹上传）
    if (extract && filename.endsWith(".zip")) {
      const tmpZip = path.join("/tmp", `upload-${Date.now()}.zip`);
      await fs.writeFile(tmpZip, buffer);

      const extractPath = targetDir ? path.join(workspacePath, targetDir) : workspacePath;
      await fs.mkdir(extractPath, { recursive: true });

      const { exec } = await import("node:child_process");
      const { promisify } = await import("node:util");
      const execAsync = promisify(exec);

      await execAsync(`unzip -o ${tmpZip} -d ${extractPath}`);
      await fs.unlink(tmpZip);

      sendJson(res, 200, {
        success: true,
        extracted: true,
        targetDir: extractPath,
        agentId,
      });
    } else {
      // 普通文件上传
      const filePath = path.join(workspacePath, filename);
      await fs.writeFile(filePath, buffer);
      const stats = await fs.stat(filePath);

      sendJson(res, 200, {
        success: true,
        filename,
        size: stats.size,
        agentId,
      });
    }
  } catch (error: any) {
    ctx.logger.error("Upload failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleUploadFolder(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { agentId, files } = await readJsonBody(req);

    if (!agentId || !Array.isArray(files) || files.length === 0) {
      sendJson(res, 400, { error: "Missing agentId or files array" });
      return true;
    }

    const workspacePath = getWorkspacePath(agentId);
    await fs.mkdir(workspacePath, { recursive: true });

    const results = [];

    for (const file of files) {
      const { path: relativePath, content } = file;

      if (!relativePath || !content) {
        results.push({ path: relativePath, error: "Missing path or content" });
        continue;
      }

      const buffer = Buffer.from(content, "base64");

      if (buffer.length > ctx.maxFileSize) {
        results.push({ path: relativePath, error: "File too large" });
        continue;
      }

      const fullPath = path.join(workspacePath, relativePath);
      const dir = path.dirname(fullPath);

      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(fullPath, buffer);

      const stats = await fs.stat(fullPath);
      results.push({ path: relativePath, size: stats.size, success: true });
    }

    sendJson(res, 200, {
      success: true,
      agentId,
      uploaded: results.filter(r => r.success).length,
      failed: results.filter(r => r.error).length,
      results,
    });
  } catch (error: any) {
    ctx.logger.error("Upload folder failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleDownload(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "GET") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const url = new URL(req.url || "/", "http://localhost");
    const agentId = url.searchParams.get("agentId");
    const filename = url.searchParams.get("path");

    if (!agentId || !filename) {
      sendJson(res, 400, { error: "agentId and path required" });
      return true;
    }

    const workspacePath = getWorkspacePath(agentId);
    const filePath = path.join(workspacePath, filename);

    const realPath = await fs.realpath(filePath).catch(() => null);
    if (!realPath || !realPath.startsWith(workspacePath)) {
      sendJson(res, 403, { error: "Access denied" });
      return true;
    }

    const content = await fs.readFile(filePath);

    sendJson(res, 200, {
      content: content.toString('base64'),
      filename,
    });
  } catch (error: any) {
    ctx.logger.error("Download failed:", error);
    sendJson(res, 404, { error: "File not found" });
  }

  return true;
}

async function handleList(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "GET") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const url = new URL(req.url || "/", "http://localhost");
    const agentId = url.searchParams.get("agentId");

    if (!agentId) {
      sendJson(res, 400, { error: "agentId required" });
      return true;
    }

    // 使用与上传/下载一致的路径解析
    const workspacePath = getWorkspacePath(agentId as string);
    let entries: any[] = [];

    try {
      entries = await fs.readdir(workspacePath, { withFileTypes: true }) as any[];
      ctx.logger.info(`[list] Found workspace at: ${workspacePath}`);
    } catch (e) {
      ctx.logger.warn(`[list] Workspace not found: ${workspacePath}`);
    }

    if (entries.length === 0) {
      sendJson(res, 200, { files: [], workspace: workspacePath });
      return true;
    }

    const files = [];

    for (const entry of entries) {
      if (entry.isFile()) {
        const filePath = path.join(workspacePath, entry.name);
        const stats = await fs.stat(filePath);
        files.push({
          name: entry.name,
          path: filePath,
          size: stats.size,
          updatedAtMs: stats.mtimeMs,
          missing: false,
        });
      }
    }

    sendJson(res, 200, { files, workspace: workspacePath });
  } catch (error: any) {
    ctx.logger.error("List failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleDelete(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { agentId, path: filename } = await readJsonBody(req);

    if (!agentId || !filename) {
      sendJson(res, 400, { error: "agentId and path required" });
      return true;
    }

    const workspacePath = getWorkspacePath(agentId);
    const filePath = path.join(workspacePath, filename);

    const realPath = await fs.realpath(filePath).catch(() => null);
    if (!realPath || !realPath.startsWith(workspacePath)) {
      sendJson(res, 403, { error: "Access denied" });
      return true;
    }

    await fs.unlink(filePath);
    sendJson(res, 200, { success: true });
  } catch (error: any) {
    ctx.logger.error("Delete failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

function getWorkspacePath(agentId: string): string {
  const base = process.env.OPENCLAW_STATE_DIR || path.join(process.env.OPENCLAW_HOME || "/home/node", ".openclaw");
  // OpenClaw 真实路径规则（见 src/agents/agent-scope.ts resolveAgentWorkspaceDir）:
  //   main（默认 agent）: ~/.openclaw/workspace
  //   其他 agent:         ~/.openclaw/workspace-{agentId}
  if (agentId === "main") {
    return path.join(base, "workspace");
  }
  return path.join(base, `workspace-${agentId}`);
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
