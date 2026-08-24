// Assemble plugins/opencode-last9/skills/ from the canonical repo tree at
// pack time. Runs via the package.json "prepack" hook; never commit the
// generated directory.
import { execSync } from "node:child_process"
import { cpSync, mkdirSync, rmSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const repoRoot = resolve(pkgDir, "../..")
const dest = resolve(pkgDir, "skills")

rmSync(dest, { recursive: true, force: true })

// Enumerate tracked canonical skills only, so untracked working-tree
// experiments never leak into a published tarball.
const out = execSync("git ls-files 'skills/*/SKILL.md'", { cwd: repoRoot })
  .toString()
  .trim()

if (!out) {
  console.error("assemble-skills: no tracked skills found — tarball will ship without skills")
  process.exit(1)
}

mkdirSync(dest, { recursive: true })
for (const rel of out.split("\n")) {
  const name = rel.split("/")[1]
  mkdirSync(resolve(dest, name), { recursive: true })
  cpSync(resolve(repoRoot, rel), resolve(dest, name, "SKILL.md"))
}
console.log(`assemble-skills: packaged ${out.split("\n").length} skills`)
