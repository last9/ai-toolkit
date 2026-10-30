#!/usr/bin/env sh
# Focused checks for last9-emit-telemetry: endpoint normalization, required
# run ID, receipt redaction, and generator output that must never include
# exporter headers.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/last9-emit-telemetry.sh"
SKILL_MD="$ROOT_DIR/skills/last9-emit-telemetry/SKILL.md"
FAILS=0

fail() {
  echo "selftest FAILED: $1" >&2
  FAILS=$((FAILS + 1))
}

pass() {
  echo "ok: $1"
}

LAST9_EMIT_TELEMETRY_LIB=1
# shellcheck disable=SC1090,SC2034
. "$HELPER"
unset LAST9_EMIT_TELEMETRY_LIB

# --- endpoint normalization ---
assert_norm() {
  _got=$(normalize_otlp_endpoint "$1")
  if [ "$_got" != "$2" ]; then
    fail "normalize '$1' => '$_got' (want '$2')"
  else
    pass "normalize '$1'"
  fi
}

assert_norm "https://otlp.example.test:443/" "otlp.example.test:443"
assert_norm "http://localhost:4317" "localhost:4317"
assert_norm "HTTPS://otlp.example.test:443" "otlp.example.test:443"
assert_norm "otlp.example.test:443" "otlp.example.test:443"
assert_norm "https://otlp.example.test:443/v1/traces/" "otlp.example.test:443"
assert_norm "  https://otlp-aps1.example.test:443  " "otlp-aps1.example.test:443"

if normalize_otlp_endpoint "https://user:pass@otlp.example.test:443" >/dev/null 2>&1; then
  fail "normalize should reject userinfo"
else
  pass "normalize rejects userinfo"
fi

if normalize_otlp_endpoint "" >/dev/null 2>&1; then
  fail "normalize should reject empty endpoint"
else
  pass "normalize rejects empty endpoint"
fi

# --- required run ID ---
if require_acceptance_run "" >/dev/null 2>&1; then
  fail "empty acceptance_run should fail"
else
  pass "empty acceptance_run refused"
fi

if require_acceptance_run "not-a-uuid" >/dev/null 2>&1; then
  fail "non-UUID acceptance_run should fail"
else
  pass "non-UUID acceptance_run refused"
fi

_valid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_got=$(require_acceptance_run "$_valid")
if [ "$_got" != "$_valid" ]; then
  fail "valid UUID not returned"
else
  pass "valid UUID accepted"
fi

_generated=$(new_acceptance_run_id)
if ! is_uuid "$_generated"; then
  fail "generated acceptance_run is not a UUID ($_generated)"
else
  pass "generated acceptance_run is a UUID"
fi

# --- receipt redaction ---
_receipt=$(build_receipt "$_valid" "example-org" "alpha" \
  '["metrics"]' '["last9.emit.telemetry"]' "last9-emit-telemetry" \
  "2026-10-30T00:00:00Z" "2026-10-30T00:00:05Z" "metrics-ds" "client_ok" "no")

if receipt_contains_forbidden "$_receipt"; then
  fail "clean receipt flagged as forbidden: $_receipt"
else
  pass "clean receipt has no forbidden keys"
fi

case "$_receipt" in
  *acceptance_run*example-org*metrics*last9.emit.telemetry*last9-emit-telemetry*metrics-ds*)
    pass "receipt carries non-secret ids"
    ;;
  *)
    fail "receipt missing expected non-secret fields: $_receipt"
    ;;
esac

_bad='{"acceptance_run":"'"$_valid"'","headers":{"Authorization":"not-a-real-credential"}}'
if receipt_contains_forbidden "$_bad"; then
  pass "receipt with headers is rejected"
else
  fail "receipt with headers was not rejected"
fi

_bad2='{"authorization":"not-a-real-credential"}'
if receipt_contains_forbidden "$_bad2"; then
  pass "receipt with authorization is rejected"
else
  fail "receipt with authorization was not rejected"
fi

# --- command argv cannot include exporter headers ---
_argv=$(build_telemetrygen_argv metrics "otlp.example.test:443" "last9-emit-telemetry" \
  "$_valid" "5s" "1" "1" "last9.emit.telemetry" "0")
if printf '%s\n' "$_argv" | grep -qiE -- 'otlp-header|Authorization=|OTEL_EXPORTER_OTLP_HEADERS|Basic '; then
  fail "argv included exporter headers"
else
  pass "argv has no exporter headers"
fi
case "$_argv" in
  *"--otlp-endpoint"*"otlp.example.test:443"*acceptance_run*)
    pass "argv includes normalized endpoint and run id"
    ;;
  *)
    fail "argv missing endpoint or run id"
    ;;
esac

# --- sanitizer never emits exporter headers ---
_secret_out=$(mktemp "${TMPDIR:-/tmp}/last9-emit-san.XXXXXX")
_secret_err=$(mktemp "${TMPDIR:-/tmp}/last9-emit-sanerr.XXXXXX")
printf '%s\n' \
  "starting gRPC exporter" \
  'headers map[Authorization:[not-a-real-credential]]' \
  "traces generated" >"$_secret_out"
set +e
sanitize_exporter_output <"$_secret_out" >"$_secret_err" 2>"$_secret_err.2"
_san_st=$?
set -e
_combined=$(cat "$_secret_err" "$_secret_err.2")
if printf '%s' "$_combined" | grep -q "not-a-real-credential"; then
  fail "sanitizer leaked token"
else
  pass "sanitizer dropped token"
fi
if printf '%s' "$_combined" | grep -qiE 'Authorization|headers map'; then
  fail "sanitizer leaked header dump"
else
  pass "sanitizer dropped header dump"
fi
if [ "$_san_st" -ne 0 ]; then
  fail "sanitizer should return 0 after suppression (export outcome is separate)"
else
  pass "sanitizer returns success after suppression"
fi
rm -f "$_secret_out" "$_secret_err" "$_secret_err.2"

_clean=$(printf '%s\n' "starting gRPC exporter" "traces generated" | sanitize_exporter_output)
case "$_clean" in
  *traces\ generated*) pass "sanitizer keeps non-secret generator lines" ;;
  *) fail "sanitizer dropped clean logs: $_clean" ;;
esac

if output_contains_exporter_headers "headers map[Authorization:[not-a-real-credential]]"; then
  pass "header detector flags exporter dumps"
else
  fail "header detector missed exporter dump"
fi
if output_contains_exporter_headers "traces generated"; then
  fail "header detector false-positive on clean logs"
else
  pass "header detector allows clean logs"
fi

# --- CLI: print-argv and dry-run, no secrets in output ---
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/last9-emit-selftest.XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT
CRED="$WORKDIR/creds.env"
printf '%s\n' \
  'OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.example.test:443/' \
  'OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic <your-api-key>' \
  >"$CRED"

_cli_out=$("$HELPER" --print-argv \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals metrics \
  --acceptance-run "$_valid")
case "$_cli_out" in
  *otlp.example.test:443*) pass "CLI print-argv uses normalized host:port" ;;
  *) fail "CLI print-argv missing normalized endpoint: $_cli_out" ;;
esac
if printf '%s' "$_cli_out" | grep -qiE -- 'otlp-header|Authorization=|Basic |<your-api-key>|https://'; then
  fail "CLI print-argv leaked header or unnormalized URL: $_cli_out"
else
  pass "CLI print-argv has no headers or scheme"
fi

_dry=$("$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals metrics,logs,traces \
  --acceptance-run "$_valid")
if receipt_contains_forbidden "$_dry"; then
  fail "dry-run receipt contained secrets: $_dry"
else
  pass "dry-run receipt redacted"
fi
case "$_dry" in
  *"\"last9_queryable\":\"no\""*) pass "dry-run does not claim queryable" ;;
  *) fail "dry-run missing last9_queryable=no: $_dry" ;;
esac
case "$_dry" in
  *"\"otlp_export\":\"not_executed\""*) pass "dry-run does not claim client export" ;;
  *) fail "dry-run missing otlp_export=not_executed: $_dry" ;;
esac

if "$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals metrics \
  --acceptance-run "" >/dev/null 2>&1; then
  fail "CLI accepted empty acceptance_run"
else
  pass "CLI refuses empty acceptance_run"
fi

if "$HELPER" --otlp-header 'Authorization="Basic <your-api-key>"' \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" >/dev/null 2>&1; then
  fail "CLI accepted --otlp-header"
else
  pass "CLI refuses --otlp-header"
fi

if "$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file 'Authorization=not-a-path' >/dev/null 2>&1; then
  fail "CLI accepted a secret as credential-file"
else
  pass "CLI refuses secret-shaped credential-file"
fi

LAST9_OTLP_CREDENTIAL_FILE="$CRED"
export LAST9_OTLP_CREDENTIAL_FILE
_env_receipt=$("$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-env LAST9_OTLP_CREDENTIAL_FILE --signals metrics \
  --acceptance-run "$_valid")
case "$_env_receipt" in
  *example-org*) pass "CLI accepts credential-env path reference" ;;
  *) fail "credential-env path reference failed: $_env_receipt" ;;
esac
unset LAST9_OTLP_CREDENTIAL_FILE

if "$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-env 'Authorization=not-a-path' >/dev/null 2>&1; then
  fail "CLI accepted a secret as credential-env name"
else
  pass "CLI refuses secret-shaped credential-env name"
fi

# Missing run id is generated, not skipped.
_gen_receipt=$("$HELPER" --dry-run \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals logs)
_gen_id=$(printf '%s' "$_gen_receipt" | sed -n 's/.*"acceptance_run":"\([^"]*\)".*/\1/p')
if is_uuid "$_gen_id"; then
  pass "CLI generates acceptance_run when omitted"
else
  fail "CLI did not generate a UUID run id: $_gen_receipt"
fi

# --- fake telemetrygen: wrapper output cannot include exporter headers ---
FAKEBIN="$WORKDIR/bin"
mkdir -p "$FAKEBIN"
printf '%s\n' '#!/bin/sh' \
  'echo "starting gRPC exporter"' \
  'echo "headers map[Authorization:[not-a-real-credential]]"' \
  'echo "traces generated"' \
  >"$FAKEBIN/telemetrygen"
chmod +x "$FAKEBIN/telemetrygen"

_wrap_err="$WORKDIR/wrap.err"
set +e
PATH="$FAKEBIN:$PATH" "$HELPER" \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals traces \
  --acceptance-run "$_valid" >"$WORKDIR/wrap.out" 2>"$_wrap_err"
_wrap_st=$?
set -e
_wrap_all=$(cat "$WORKDIR/wrap.out" "$_wrap_err")
if printf '%s' "$_wrap_all" | grep -q "not-a-real-credential"; then
  fail "wrapper leaked fake telemetrygen token"
else
  pass "wrapper suppressed fake telemetrygen token"
fi
if printf '%s' "$_wrap_all" | grep -qiE 'headers map|Authorization='; then
  fail "wrapper leaked exporter header dump"
else
  pass "wrapper suppressed exporter header dump"
fi
if [ "$_wrap_st" -ne 0 ]; then
  fail "wrapper should succeed when fake telemetrygen exits 0 (got $_wrap_st)"
else
  pass "wrapper reports client success without echoing headers"
fi
if grep -q '"otlp_export":"client_ok"' "$WORKDIR/wrap.out" && grep -q '"last9_queryable":"no"' "$WORKDIR/wrap.out"; then
  pass "wrapper distinguishes client export from Last9 queryability"
else
  fail "wrapper receipt missing export/queryable split: $(cat "$WORKDIR/wrap.out")"
fi

# --- SKILL.md still encodes the same gates ---
for _needle in \
  "acceptance_run" \
  "host:port" \
  "credential" \
  "last9_queryable" \
  "ingestion_propagation" \
  "wrong_datasource" \
  "query_path_timeout" \
  "separate user authorization" \
  "--otlp-header"
 do
  if grep -Fq -- "$_needle" "$SKILL_MD"; then
    pass "SKILL.md mentions $_needle"
  else
    fail "SKILL.md missing $_needle"
  fi
done

if [ "$FAILS" -ne 0 ]; then
  echo "last9-emit-telemetry selftests failed: $FAILS" >&2
  exit 1
fi
echo "last9-emit-telemetry selftests passed"
