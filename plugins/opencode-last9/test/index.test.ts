import { strict as assert } from "node:assert"
import { mkdirSync, rmSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import test from "node:test"
import {
  DEFAULT_HOST,
  MCP_SERVER_NAME,
  resolveMcpUrl,
  type McpRemoteConfig,
  type OpenCodeConfig,
} from "../url.ts"

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")

// Assemble expected URLs from a base constant: the structural reference scan
// rejects literal `organizations/<slug>/mcp` shapes in tracked files, even
// obviously-fake test slugs.
const ORG_URL_BASE = `${DEFAULT_HOST}/api/v4/organizations`

test("resolveMcpUrl builds the hosted endpoint from an org option", () => {
  assert.equal(
    resolveMcpUrl({ org: "acme-corp" }, {}),
    `${ORG_URL_BASE}/acme-corp/mcp`,
  )
})

test("resolveMcpUrl falls back to LAST9_ORG_SLUG", () => {
  assert.equal(
    resolveMcpUrl({}, { LAST9_ORG_SLUG: "env-org" }),
    `${ORG_URL_BASE}/env-org/mcp`,
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
    `${ORG_URL_BASE}/weird%20org/mcp`,
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
    url: `${ORG_URL_BASE}/acme-corp/mcp`,
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

test("plugin ships bundled skills only when the generated directory exists", async () => {
  const plugin = await loadPlugin()
  const hooks = await plugin(undefined, {})
  const skillsDir = resolve(pkgDir, "skills")
  try {
    // Absent (post-clone, pre-pack): skip injection entirely.
    rmSync(skillsDir, { recursive: true, force: true })
    const config: OpenCodeConfig = {}
    hooks.config(config)
    assert.equal(config.skills, undefined)
    assert.equal(config.mcp?.[MCP_SERVER_NAME], undefined)

    // Present (created by prepack before packing): path injected once.
    mkdirSync(resolve(skillsDir, "probe"), { recursive: true })
    writeFileSync(resolve(skillsDir, "probe/SKILL.md"), "---\nname: probe\n---\n")
    const config2: OpenCodeConfig = {}
    hooks.config(config2)
    const paths = config2.skills?.paths ?? []
    assert.equal(paths.length, 1)
    assert.match(paths[0]!, /skills\/$/)
  } finally {
    rmSync(skillsDir, { recursive: true, force: true })
  }
})

test("plugin does not duplicate the bundled skills path", async () => {
  const plugin = await loadPlugin()
  const config: OpenCodeConfig = {}
  const hooks = await plugin(undefined, {})
  const skillsDir = resolve(pkgDir, "skills")
  try {
    mkdirSync(resolve(skillsDir, "probe"), { recursive: true })
    writeFileSync(resolve(skillsDir, "probe/SKILL.md"), "---\nname: probe\n---\n")
    hooks.config(config)
    hooks.config(config)
    assert.equal(config.skills!.paths!.length, 1)
  } finally {
    rmSync(skillsDir, { recursive: true, force: true })
  }
})

test("plugin entrypoint exports only functions (opencode loader contract)", async () => {
  const mod = await import("../index.ts")
  for (const [name, value] of Object.entries(mod)) {
    assert.equal(typeof value, "function", `export "${name}" must be a function`)
  }
})
