// Acceptance probe for the eMudhra CA compromise (#23): the running Node must
// reject a chain through a blocklisted intermediate yet still trust a normal
// HTTPS endpoint. Exits non-zero when either expectation fails.
const REVOKED_URL = "https://dv-g3b-emudhra.we-have-a-problem.com/"
const TRUSTED_URL = "https://registry.npmjs.org/"

async function probe(url) {
  try {
    const res = await fetch(url, { method: "HEAD" })
    return { ok: true, detail: `HTTP ${res.status}` }
  } catch (err) {
    const cause = err.cause ?? err
    return { ok: false, code: cause.code, detail: `${cause.code ?? ""} ${cause.message}` }
  }
}

console.log(`process.version=${process.version}`)
const revoked = await probe(REVOKED_URL)
const trusted = await probe(TRUSTED_URL)
console.log(`${REVOKED_URL} -> ${revoked.detail}`)
console.log(`${TRUSTED_URL} -> ${trusted.detail}`)

let failed = false
if (revoked.code !== "CERT_REVOKED") {
  console.error(`expected CERT_REVOKED from ${REVOKED_URL}`)
  failed = true
}
if (!trusted.ok) {
  console.error(`expected ${TRUSTED_URL} to connect`)
  failed = true
}
process.exit(failed ? 1 : 0)
