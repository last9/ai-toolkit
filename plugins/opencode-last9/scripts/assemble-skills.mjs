// Assemble plugins/opencode-last9/skills/ from the canonical repo tree at
// pack time. Runs via the package.json "prepack" hook; never commit the
// generated directory.
import { execSync } from "node:child_process"
import { cpSync, mkdirSync, rmSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const pkgDir = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const repoRoot = resolve(pkgDir, "../..")
const dest = resolve(pkgDir, "skills")

rmSync(dest, { recursive: true, force: true })

// Enumerate tracked canonical content only, so untracked working-tree
// experiments never leak into a published tarball.
const out = execSync("git ls-files 'skills/**'", { cwd: repoRoot })
  .toString()
  .trim()

if (!out) {
  console.error("assemble-skills: no tracked skills found — tarball will ship without skills")
  process.exit(1)
}

const files = out.split("\n").map((rel) => rel.split("/"))
mkdirSync(dest, { recursive: true })
for (const segs of files) {
  if (segs[0] !== "skills" || segs.length < 3) {
    console.error(`assemble-skills: unexpected path '${segs.join("/")}' — expected skills/<name>/...`)
    process.exit(1)
  }
  const name = segs[1]
  const source = resolve(repoRoot, ...segs)
  const target = resolve(dest, name, ...segs.slice(2))
  mkdirSync(dirname(target), { recursive: true })
  cpSync(source, target)
}

// Fail loudly if assembly does not match the tracked set — a partial tree
// here would ship silently incomplete skills.
const expected = files.length
const assembled = execSync(`find ${JSON.stringify(dest)} -type f | wc -l`).toString().trim()
if (Number(assembled) !== expected) {
  console.error(`assemble-skills: assembled ${assembled} files, expected ${expected}`)
  process.exit(1)
}
console.log(`assemble-skills: packaged ${expected} files across ${new Set(files.map((s) => s[1])).size} skills`)
