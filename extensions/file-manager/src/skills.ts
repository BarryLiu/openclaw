import type { IncomingMessage, ServerResponse } from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

export function createSkillManagerHttpHandler(params: { logger: any }) {
  const { logger } = params;

  return async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
    const url = new URL(req.url || "/", "http://localhost");
    const pathname = url.pathname;

    if (pathname === "/plugins/file-manager/skills/install") {
      return handleInstall(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/skills/uninstall") {
      return handleUninstall(req, res, { logger });
    }

    if (pathname === "/plugins/file-manager/skills/list") {
      return handleList(req, res, { logger });
    }

    return false;
  };
}

async function handleInstall(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { title, files } = await readJsonBody(req);

    if (!title || !Array.isArray(files) || files.length === 0) {
      sendJson(res, 400, { error: "Missing title or files array" });
      return true;
    }

    const skillsDir = getSkillsDir();
    const skillDir = path.join(skillsDir, title);

    await fs.mkdir(skillDir, { recursive: true });

    const results = [];

    for (const file of files) {
      const { path: relativePath, content } = file;

      if (!relativePath || !content) {
        results.push({ path: relativePath, error: "Missing path or content" });
        continue;
      }

      const buffer = Buffer.from(content, "base64");
      const fullPath = path.join(skillDir, relativePath);
      const dir = path.dirname(fullPath);

      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(fullPath, buffer);

      const stats = await fs.stat(fullPath);
      results.push({ path: relativePath, size: stats.size, success: true });
    }

    ctx.logger.info(`Skill installed: ${title} (${results.filter(r => r.success).length} files)`);
    sendJson(res, 200, {
      ok: true,
      message: `${title} installed`,
      uploaded: results.filter(r => r.success).length,
      failed: results.filter(r => r.error).length,
    });
  } catch (error: any) {
    ctx.logger.error("Install failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleUninstall(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const { title } = await readJsonBody(req);

    if (!title) {
      sendJson(res, 400, { error: "Missing title" });
      return true;
    }

    const skillsDir = getSkillsDir();
    const skillDir = path.join(skillsDir, title);

    await fs.rm(skillDir, { recursive: true, force: true });

    ctx.logger.info(`Skill uninstalled: ${title}`);
    sendJson(res, 200, { ok: true, message: `${title} uninstalled` });
  } catch (error: any) {
    ctx.logger.error("Uninstall failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

async function handleList(req: IncomingMessage, res: ServerResponse, ctx: any): Promise<boolean> {
  if (req.method !== "GET") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }

  try {
    const skillsDir = getSkillsDir();
    const entries = await fs.readdir(skillsDir, { withFileTypes: true }).catch(() => []);
    const skills = entries.filter(e => e.isDirectory()).map(e => e.name);

    sendJson(res, 200, { ok: true, skills });
  } catch (error: any) {
    ctx.logger.error("List failed:", error);
    sendJson(res, 500, { error: error.message });
  }

  return true;
}

function getSkillsDir(): string {
  const base = process.env.OPENCLAW_HOME || "/home/node/.openclaw";
  return path.join(base, "workspace", "skills");
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
