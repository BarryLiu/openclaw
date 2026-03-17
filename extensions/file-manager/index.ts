import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { Type } from "@sinclair/typebox";
import { createFileManagerHttpHandler } from "./src/http.js";
import { createSkillManagerHttpHandler } from "./src/skills.js";
import { createPluginUpdateHttpHandler } from "./src/update.js";

const configSchema = Type.Object({
  maxFileSize: Type.Optional(Type.Number({ default: 100 * 1024 * 1024 })),
  allowedExtensions: Type.Optional(Type.Array(Type.String())),
});

const plugin = {
  id: "file-manager",
  name: "File Manager",
  description: "File upload/download/management for agent workspaces and skills",
  configSchema,
  register(api: OpenClawPluginApi) {
    const maxFileSize = api.pluginConfig?.maxFileSize ?? 100 * 1024 * 1024;

    api.registerHttpRoute({
      path: "/plugins/file-manager",
      auth: "gateway",
      match: "prefix",
      handler: async (req, res) => {
        const fileHandler = createFileManagerHttpHandler({ api, maxFileSize, logger: api.logger });
        const skillHandler = createSkillManagerHttpHandler({ logger: api.logger });
        const updateHandler = createPluginUpdateHttpHandler({ logger: api.logger });

        return (await updateHandler(req, res)) || (await skillHandler(req, res)) || (await fileHandler(req, res));
      },
    });

    api.logger.info("File Manager plugin registered (files + skills + update)");
  },
};

export default plugin;
