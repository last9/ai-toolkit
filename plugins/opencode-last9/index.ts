import { existsSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { MCP_SERVER_NAME, resolveMcpUrl, type OpenCodeConfig } from "./url.ts"

function bundledSkillsPath(): string | undefined {
  try {
    const path = fileURLToPath(new URL("./skills/", import.meta.url))
    return existsSync(path) ? path : undefined
  } catch {
    return undefined
  }
}

export const Last9Plugin = async (
  _input?: unknown,
  options: Parameters<typeof resolveMcpUrl>[0] = {},
) => {
  return {
    config: (config: OpenCodeConfig): void => {
      config.mcp ??= {}

      // Never clobber an entry the user already defined (project or global config).
      if (!config.mcp[MCP_SERVER_NAME]) {
        const url = resolveMcpUrl(options)
        if (url) {
          config.mcp[MCP_SERVER_NAME] = {
            type: "remote",
            url,
            enabled: true,
          }
        }
      }

      // Ship the canonical Last9 investigation skills alongside the tools.
      const skillsDir = bundledSkillsPath()
      if (skillsDir) {
        config.skills ??= {}
        config.skills.paths ??= []
        if (!config.skills.paths.includes(skillsDir)) {
          config.skills.paths.push(skillsDir)
        }
      }
    },
  }
}

export default Last9Plugin
