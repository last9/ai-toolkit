export const DEFAULT_HOST = "https://app.last9.io"
export const MCP_SERVER_NAME = "last9"

/**
 * Options accepted via the tuple form in opencode.json:
 *
 *   "plugin": [["@last9/opencode-plugin", { "org": "<org-slug>" }]]
 */
export interface Last9PluginOptions {
  /** Your Last9 org slug (the part after app.last9.io/ in your browser URL). */
  org?: string
  /** Full MCP endpoint URL. Overrides `org`; useful for self-hosted or preview environments. */
  url?: string
}

/** Minimal structural types — keeps the plugin dependency-free and tolerant of opencode config evolution. */
export interface McpRemoteConfig {
  type: "remote"
  url: string
  enabled: boolean
}

export interface OpenCodeConfig {
  mcp?: Record<string, McpRemoteConfig>
  skills?: { paths?: string[] }
}

/**
 * Resolve the Last9 MCP endpoint.
 *
 * Precedence: explicit `url` option > `LAST9_MCP_URL` env >
 * `org` option > `LAST9_ORG_SLUG` env > undefined (no injection).
 *
 * Lives outside the plugin entrypoint because opencode's loader requires
 * every export of the entrypoint module to be a function.
 */
export function resolveMcpUrl(
  options: Last9PluginOptions = {},
  env: NodeJS.ProcessEnv = process.env,
): string | undefined {
  const explicit = (options.url ?? env.LAST9_MCP_URL ?? "").trim()
  if (explicit) return explicit.replace(/\/+$/, "")

  const org = (options.org ?? env.LAST9_ORG_SLUG ?? "").trim()
  if (!org) return undefined

  return `${DEFAULT_HOST}/api/v4/organizations/${encodeURIComponent(org)}/mcp`
}
