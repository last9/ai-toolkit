import { strict as assert } from "node:assert"
import { readFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import test from "node:test"

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")

// First release on each supported line carrying the eMudhra SPKI blocklist
// (nodejs/node#66871). Lines without a patched release stay out of `engines`.
const PATCHED_FLOORS: Record<number, [number, number, number]> = {
  22: [22, 23, 4],
  24: [24, 22, 1],
}

function parseExact(version: string): [number, number, number] {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version)
  assert.ok(match, `expected an exact x.y.z version, got ${JSON.stringify(version)}`)
  return [Number(match[1]), Number(match[2]), Number(match[3])]
}

function atLeast(a: number[], b: number[]): boolean {
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] > b[i]
  }
  return true
}

test(".nvmrc pins an exact Node release on a patched line", () => {
  const pinned = readFileSync(resolve(pkgDir, ".nvmrc"), "utf8").trim()
  const version = parseExact(pinned)
  const floor = PATCHED_FLOORS[version[0]]
  assert.ok(floor, `Node ${version[0]} has no release with the blocklist fix`)
  assert.ok(atLeast(version, floor), `${pinned} predates the fixed ${floor.join(".")}`)
})

test("engines.node admits only patched releases of supported lines", () => {
  const pkg = JSON.parse(readFileSync(resolve(pkgDir, "package.json"), "utf8"))
  const expected = Object.values(PATCHED_FLOORS)
    .map((floor) => `^${floor.join(".")}`)
    .join(" || ")
  assert.equal(pkg.engines.node, expected)
})
