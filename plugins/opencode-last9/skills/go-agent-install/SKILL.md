---
name: go-agent-install
description: Install Last9 go-agent instrumentation into a Go service — base setup, chi router, database/sql tracing, and opt-in features like HTTP request/response body capture, with build and telemetry verification. Use when the user wants to add Last9 tracing to a Go app, "install go-agent", "instrument my Go service with Last9", "add Last9 tracing to chi", or "capture request/response bodies".
metadata:
  author: last9
---

# go-agent-install — add Last9 go-agent to a Go service

This skill **edits the customer's repository**. It detects the stack, shows a diff plan, applies minimal edits, promotes the features worth turning on, then verifies telemetry reaches Last9. v1 auto-wires base + chi + `database/sql`; other frameworks fall back to base + db with the manual snippet.

`go-agent` is the SDK path — one `agent.Start()` replaces the OpenTelemetry SDK setup, and each integration is a drop-in replacement for the standard constructor.

## Prerequisites

Run only inside a Go module. If there is no `go.mod` at or above the working directory, **stop** and tell the user this isn't a Go module — there is nothing to instrument.

## Workflow

### 1. Detect the stack

Read `go.mod` and the `main` package. Determine:

- **HTTP framework** — inspect the `require` block and the router construction:
  - `github.com/go-chi/chi` → chi. **Auto-wire it** (step 4).
  - gin / echo / gorilla / grpc / fasthttp / iris / beego → **not auto-wired in v1**. Wire base + db only, tell the user chi is the only auto-wired framework today, and hand them the manual snippet from [Other frameworks](#other-frameworks-manual).
- **SQL driver** — map the imported driver to a `DriverName`: `github.com/lib/pq` → `postgres`, `github.com/jackc/pgx` → `pgx`, `github.com/go-sql-driver/mysql` → `mysql`, `github.com/mattn/go-sqlite3` → `sqlite3`, `modernc.org/sqlite` → `sqlite`.
- **Existing instrumentation** — if a `go.opentelemetry.io/...` SDK init, an `otelgin`/`otelchi`-style middleware, or a prior `github.com/last9/go-agent` import is present, this is a **conflict**. Do not double-instrument. Report what you found and **stop** for user direction.

### 2. Confirm the plan

Show the detected stack and the **exact edits** (as a diff preview) before touching any file. Get one explicit confirmation. A single yes/no — not an interview.

### 3. Wire base

1. Add the dependency: `go get github.com/last9/go-agent`
2. In `main`, add the first two lines (and the import):
   ```go
   import agent "github.com/last9/go-agent"

   func main() {
       agent.Start()
       defer agent.Shutdown()

       // existing code, unchanged
   }
   ```
3. Surface the three environment variables. Read existing values from the shell or a `.env`; if absent, prompt the user. **Never write a token into a tracked file.**
   ```
   OTEL_EXPORTER_OTLP_ENDPOINT="<your last9 otlp endpoint>"
   OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your last9 token>"
   OTEL_SERVICE_NAME="<service name>"
   ```

### 4. Wire chi

`chiagent.New()` alone does **not** instrument — Chi captures the route pattern only when the middleware is applied *after* routes are defined. Always finish with `chiagent.Use(r)` and serve the handler it returns:

```go
import chiagent "github.com/last9/go-agent/instrumentation/chi"

r := chiagent.New()           // or keep an existing chi.NewRouter()
r.Get("/users/{id}", handler) // define ALL routes first
handler := chiagent.Use(r)    // REQUIRED — returns the instrumented http.Handler
http.ListenAndServe(":8080", handler)
```

Without the `chiagent.Use(r)` call, no server spans are produced. Do not instead call `r.Use(...)` here — Chi v5 panics when middleware is added after routes.

### 5. Wire database

Replace `sql.Open(...)` with `database.Open(...)`. Every query gets a span; connection-pool metrics and DSN attributes (host, port, user, db name) come automatically.

```go
import "github.com/last9/go-agent/integrations/database"

db, err := database.Open(database.Config{
    DriverName:   "postgres", // from detection: postgres | pgx | mysql | sqlite3
    DSN:          dsn,         // reuse the existing DSN expression
    DatabaseName: "<db name>",
})
```

Supported drivers: `postgres`, `pgx`, `mysql`, `sqlite`, `sqlite3`. A `database.MustOpen` panic-on-error variant exists for quick init. **GORM:** don't replace it — use the official `gorm.io/plugin/opentelemetry` plugin *alongside* `database.Open` for two-layer (ORM span + wire-level SQL span) tracing; go-agent does not wrap GORM.

### 6. Promote features

After the core wiring builds, tell the user what go-agent gives them beyond basic spans, and offer to turn on the opt-in ones. Don't silently enable anything that changes data captured.

- **Already on, no action** — `agent.Start()` automatically stamps **`code.*` call-site attributes** (`code.function`, `code.filepath`, `code.lineno`) onto Client/Producer/Consumer spans, so you see *where* an outbound call originated. No config, no hot-path cost on Server/Internal spans.

- **HTTP request/response body capture** — the `httpcapture` middleware records bodies onto the span as `http.request.body` / `http.response.body`. **Opt-in, off by default.** Offer it, with the trade-off: enable only after confirming payloads carry no PII or credentials; for production prefer redacting at the collector. It must run **inside** the tracing middleware so the span is already active. Canonical wiring (net/http, from go-agent docs):
  ```go
  import (
      nethttpagent "github.com/last9/go-agent/instrumentation/nethttp"
      "github.com/last9/go-agent/instrumentation/httpcapture"
  )
  http.ListenAndServe(":8080", nethttpagent.WrapHandler(httpcapture.Middleware(mux)))
  ```
  Placement differs per framework (for chi, the `chiagent.Use(r)` span wrapper must stay outermost). Follow go-agent's HTTP Body Capture docs for the framework in use, and **verify** that `http.request.body`/`http.response.body` actually land on a span before relying on it.
  ```bash
  export LAST9_BODY_CAPTURE_ENABLED=true            # default false
  export LAST9_BODY_CAPTURE_MAX_BYTES=4096          # default 8192
  export LAST9_BODY_CAPTURE_ON_ERROR_ONLY=true      # only status >= 400; no alloc on success
  export LAST9_BODY_CAPTURE_CONTENT_TYPES="application/json,application/xml,text/plain" # this is the default
  ```

- **Log-trace correlation** — if the app uses `log/slog` or Uber `zap`, offer to swap in `github.com/last9/go-agent/instrumentation/slog` (or the zap equivalent) so `trace_id`/`span_id` get injected into log lines — jump from a log straight to its trace.

Mention these; wire the ones the user accepts. Note: don't add per-operation metric instrumentation — Last9 derives RED metrics from spans server-side.

### 7. Verify

See [Verification](#verification).

## Other frameworks (manual)

v1 auto-wires chi only. For a detected non-chi framework, wire base + db automatically and hand the user the matching drop-in (each replaces the standard constructor):

| Framework | Drop-in |
|-----------|---------|
| net/http | `nethttpagent.NewServeMux()` |
| Gin | `ginagent.Default()` / `ginagent.New()` |
| Echo | `echoagent.New()` |
| Gorilla Mux | `gorillaagent.NewRouter()` |
| gRPC | `grpcagent.NewServer()` + `grpcagent.NewClientDialOption()` |
| fasthttp | `fasthttpagent.Middleware(handler)` |
| Iris | `irisagent.New()` |
| Beego | `beegoagent.New()` |

Import path pattern: `github.com/last9/go-agent/instrumentation/<framework>`. The package name is the bare framework (`gin`, `echo`, …), so alias it to avoid colliding with the upstream import — e.g. `import ginagent "github.com/last9/go-agent/instrumentation/gin"`.

## Edge cases — stop or ask, don't guess

These break a naive run. Handle each explicitly; never paper over with a guess:

- **No `main`, or several `main` packages** (e.g. `cmd/api/main.go` + `cmd/worker/main.go`) — `agent.Start()` goes in the entrypoint that runs the server. If there's more than one, **ask which** binary to instrument; don't edit all of them.
- **Router built in a helper, not `main`** — the framework constructor may live in a `setupRouter()` / `NewServer()` function. Wire it where the router is *constructed*, not where it's used. Find the construction site before editing.
- **More than one HTTP framework present** (e.g. chi *and* gin) — ambiguous. **Ask** which serves the traffic you're instrumenting; wire one.
- **No SQL driver at all** — skip the database step entirely. Do not fabricate a `database.Open` for a service that has no SQL.
- **Dynamic / non-literal DSN** — reuse the existing DSN variable or expression in `database.Config{DSN: ...}`. Never inline a hardcoded connection string, and never a password.
- **Vendored dependencies** (`vendor/` + `-mod=vendor`) — `go get` won't update vendored modules; run `go mod vendor` after adding the dependency, or tell the user to.
- **`go get` fails** (proxy, private module, network) — report the exact error and **stop**; don't guess a workaround.
- **`golangci-lint` not installed** — say so, fall back to `go vet ./...`, and report that lint was skipped because the tool is missing. Don't silently skip.
- **App can't run locally** (needs a DB, secrets, or external config you don't have) — the build can still pass, but say plainly that end-to-end telemetry is **unverified** and what's needed to verify it. Never claim spans arrived when you didn't see them.

## Edit guardrails

This skill mutates the customer's repo. Hold these lines:

- **Dry-run first** — show every edit as a diff; apply only after the step-2 confirmation.
- **Never break the build** — run `go build ./...` *before* editing. If it already fails, report that and **stop** — don't own pre-existing breakage.
- **No secrets in code** — environment variables via the shell or `.env` only; never a token in a tracked file.
- **Conflict-aware / idempotent** — if go-agent is already wired, or another OTel SDK is present, **stop** (see Detect). Never double-instrument.
- **Body capture is consent-gated** — never enable `httpcapture` without the user explicitly accepting the PII trade-off.
- **Minimal diff** — change the import, the constructor, and the db open only. Touch nothing else.

## Verification

1. **Build** — `go build ./...` must pass after the edits.
2. **The repo's own checks, if present** — run them and **report** the result (never skip silently):
   - `golangci-lint run` when a `.golangci.y*ml` exists.
   - `make build` / `make lint` / `make test` when the `Makefile` defines them.
   - `go vet ./...` as a fallback.
3. **Telemetry, end-to-end** — run the app, hit one instrumented endpoint, then hand off to the `last9-traces` skill to confirm the spans arrive in Last9. `agent.Shutdown()` flushes on exit, but a blocking server never returns — rely on the batch processor's periodic flush (tunable via `OTEL_BSP_SCHEDULE_DELAY`) or stop the process cleanly. Use the real run path — not a simulated curl against a mock.
   - **No prod creds yet?** go-agent has no stdout exporter, but you can point `OTEL_EXPORTER_OTLP_ENDPOINT` at a local OTLP/HTTP sink (an OpenTelemetry Collector with a `debug` exporter, or any listener on `/v1/traces`) and confirm a span appears — same export path, no production token. Seeing a `SPAN_KIND_SERVER` span named by route pattern (e.g. `/users/{id}`) confirms the HTTP layer is wired correctly.

### If something is wrong

- **Build breaks** — missing import (`agent`, `chiagent`, `database`), or `go get`/`go mod tidy` not run.
- **No spans in Last9** — env vars not exported into the process; bad endpoint (connection error) or bad token (401/403); process exited before `agent.Shutdown()` flushed; or no request was sent to an instrumented route.
- **Duplicate spans** — a prior OTel SDK/middleware is still wired alongside go-agent. Remove one. (This is why detection stops on a conflict.)

## Related skills

- `last9-traces` — confirm the spans you just produced are landing in Last9.
- `last9-logs` — verify log-trace correlation once traces flow.
