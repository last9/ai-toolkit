import { strict as assert } from "node:assert"
import test from "node:test"
import {
  DEFAULT_HOST,
  MCP_SERVER_NAME,
  resolveMcpUrl,
  type McpRemoteConfig,
  type OpenCodeConfig,
} from "../url.ts"

test("resolveMcpUrl builds the hosted endpoint from an org option", () => {
  assert.equal(
    resolveMcpUrl({ org: "acme-corp" }, {}),
    `${DEFAULT_HOST}/api/v4/organizations/acme-corp/mcp`,
  )
})

test("resolveMcpUrl falls back to LAST9_ORG_SLUG", () => {
  assert.equal(
    resolveMcpUrl({}, { LAST9_ORG_SLUG: "env-org" }),
    `${DEFAULT_HOST}/api/v4/organizations/env-org/mcp`,
  )
})

test("resolveMcpUrl prefers an explicit url over org", () => {
  assert.equal(
    resolveMcpUrl({ org: "acme-corp", url: "https://preview.last9.io/mcp/" }, {}),
    "https://preview.last9.io/mcp",
  )
})

test("resolveMcpUrl falls back to LAST9_MCP_URL and trims trailing slashes", () => {
  assert.equal(resolveMcpUrl({}, { LAST9_MCP_URL: "https://self.hosted/api/mcp///" }), "https://self.hosted/api/mcp")
})

test("resolveMcpUrl returns undefined when nothing is configured", () => {
  assert.equal(resolveMcpUrl({}, {}), undefined)
  assert.equal(resolveMcpUrl({ org: "   " }, {}), undefined)
})

test("resolveMcpUrl encodes unusual org slugs", () => {
  assert.equal(
    resolveMcpUrl({ org: "weird org" }, {}),
    `${DEFAULT_HOST}/api/v4/organizations/weird%20org/mcp`,
  )
})

type PluginModule = typeof import("../index.ts")
const loadPlugin = async (): Promise<PluginModule["default"]> => (await import("../index.ts")).default

test("plugin injects the last9 MCP server into an empty config", async () => {
  const plugin = await loadPlugin()
  const config: OpenCodeConfig = {}
  const hooks1 = await plugin(undefined, { org: "acme-corp" })
  hooks1.config(config)
  assert.deepEqual(config.mcp?.[MCP_SERVER_NAME], {
    type: "remote",
    url: `${DEFAULT_HOST}/api/v4/organizations/acme-corp/mcp`,
    enabled: true,
  })
})

test("plugin never clobbers a user-defined last9 entry", async () => {
  const plugin = await loadPlugin()
  const userEntry: McpRemoteConfig = { type: "remote", url: "https://mine.example.com/mcp", enabled: false }
  const config: OpenCodeConfig = { mcp: { [MCP_SERVER_NAME]: userEntry } }
  const hooks2 = await plugin(undefined, { org: "acme-corp" })
  hooks2.config(config)
  assert.equal(config.mcp![MCP_SERVER_NAME], userEntry)
})

test("plugin skips MCP injection without org or url but still ships skills", async () => {
  const plugin = await loadPlugin()
  const config: OpenCodeConfig = {}
  const hooks1 = await plugin(undefined, {})
  hooks1.config(config)
  assert.equal(config.mcp?.[MCP_SERVER_NAME], undefined)
  const paths = config.skills?.paths ?? []
  assert.equal(paths.length, 1)
  assert.match(paths[0]!, /skills\/$/)
})

test("plugin does not duplicate the bundled skills path", async () => {
  const plugin = await loadPlugin()
  const config: OpenCodeConfig = {}
  const hooks = await plugin(undefined, {})
  hooks.config(config)
  hooks.config(config)
  assert.equal(config.skills!.paths!.length, 1)
})

test("plugin entrypoint exports only functions (opencode loader contract)", async () => {
  const mod = await import("../index.ts")
  for (const [name, value] of Object.entries(mod)) {
    assert.equal(typeof value, "function", `export "${name}" must be a function`)
  }
})
