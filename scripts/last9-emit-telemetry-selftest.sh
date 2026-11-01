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

# A matching line must not let the rest of a variable name reach eval.
# Check the side effect as well as status: injected code can run before failure.
_injected_name=$(printf 'PATH}\nprintf injected > "%s"\n#\nPATH' "$WORKDIR/executed")
for _bad_name in "$_injected_name" 'PATH
PATH' 'PATH
' '1PATH' 'PATH-NAME' "$(printf 'PATH\r\nPATH')"; do
  if "$HELPER" --dry-run \
    --org example-org --environment alpha --datasource metrics-ds \
    --credential-env "$_bad_name" --acceptance-run "$_valid" \
    >"$WORKDIR/env.out" 2>"$WORKDIR/env.err"; then
    fail "CLI accepted invalid credential variable name"
  elif [ -s "$WORKDIR/env.out" ] ||
    [ "$(cat "$WORKDIR/env.err")" != 'credential env must be a variable name, not a value' ]; then
    fail "invalid credential variable name bypassed private validation"
  else
    pass "CLI rejects entire invalid credential variable name"
  fi
  if [ -e "$WORKDIR/executed" ]; then
    fail "credential variable name executed shell code"
    rm -f "$WORKDIR/executed"
  fi
done

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

# --- preflight: invalid requests must never start a generator ---
# The marker also catches partial writes when a later signal is invalid.
cat >"$FAKEBIN/telemetrygen" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$EMIT_TEST_CALLS"
exit 0
EOF
export EMIT_TEST_CALLS="$WORKDIR/calls"
expect_preflight_failure() {
  rm -f "$EMIT_TEST_CALLS"
  if PATH="$FAKEBIN:$PATH" "$HELPER" \
    --org example-org --environment alpha --datasource metrics-ds \
    --credential-file "$CRED" --acceptance-run "$_valid" \
    "$@" >"$WORKDIR/preflight.out" 2>"$WORKDIR/preflight.err"; then
    fail "preflight accepted $1"
  elif [ -e "$EMIT_TEST_CALLS" ]; then
    fail "preflight started a generator before rejecting $1"
  else
    pass "preflight refuses $1 before emitting"
  fi
}
for _bad_signals in '' ',' 'metrics,bogus' 'metrics,metrics' 'metrics,' 'metrics,,logs' 'metrics logs' '*'; do
  expect_preflight_failure --signals "$_bad_signals"
done
for _bad_rate in 0 0.0 0e0 -0 00 -1 NaN Inf 1e999 101 '1
--otlp-insecure'; do
  expect_preflight_failure --rate "$_bad_rate"
done
for _bad_duration in 0s 0ms 0.0s -1s -1ns inf INF Inf iNf 1h 61s 60001ms '5s
--otlp-insecure'; do
  expect_preflight_failure --duration "$_bad_duration"
done
for _bad_workers in 0 -1 1.5 11 1000000 '1
--otlp-insecure'; do
  expect_preflight_failure --workers "$_bad_workers"
done
expect_preflight_failure --service 'line1
line2'
expect_preflight_failure --rate
expect_preflight_failure --service header-test
expect_preflight_failure --acceptance-run "$_valid
--otlp-insecure"
expect_preflight_failure --acceptance-run "$_valid
"

for _limits in '5s 1 1' '59s 99 9' '60s 100 10' '60000ms .1 1' '0.5s 0.1 1'; do
  # Intentional splitting of constant test tuples, never of user input.
  set -- $_limits
  if "$HELPER" --dry-run --org example-org --environment alpha \
    --datasource metrics-ds --credential-file "$CRED" --signals traces \
    --duration "$1" --rate "$2" --workers "$3" >"$WORKDIR/bounds.out"; then
    pass "valid bounded limits accepted"
  else
    fail "valid bounded limits rejected"
  fi
done

# Endpoint text is serialized one argument per line, so reject line breaks,
# queries, fragments and unsupported schemes before serializing anything.
for _bad_endpoint in 'https://host:443?secret=value' 'https://host:443#fragment' \
  'ftp://host:443' 'https://host:0' 'https://host:65536' 'https://host:abc' \
  'https://host:443
--otlp-insecure'; do
  if normalize_otlp_endpoint "$_bad_endpoint" >/dev/null 2>&1; then
    fail "invalid endpoint accepted"
  else
    pass "invalid endpoint refused"
  fi
done

# Never echo a rejected argument, including split and --flag=value spellings.
assert_private_rejection() {
  if "$HELPER" "$@" >"$WORKDIR/rejected.out" 2>"$WORKDIR/rejected.err"; then
    fail "credential-shaped argument accepted"
  elif grep -q 'example-secret-marker' "$WORKDIR/rejected.out" "$WORKDIR/rejected.err"; then
    fail "rejected credential argument echoed"
  else
    pass "rejected credential argument stays private"
  fi
}
for _flag in --otlp-header --header; do
  assert_private_rejection "$_flag" 'Authorization=Bearer example-secret-marker'
  assert_private_rejection "$_flag=Authorization=Bearer example-secret-marker"
done
assert_private_rejection '--unknown=example-secret-marker'
assert_private_rejection 'example-secret-marker'

# A receipt must describe the metric actually passed to the child, including
# its possible Prometheus spelling. Non-metrics runs have no metric names.
cat >"$FAKEBIN/telemetrygen" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$EMIT_TEST_ARGV"
EOF
export EMIT_TEST_ARGV="$WORKDIR/metric.argv"
assert_metric_receipt() {
  _test_signals=$1
  _expected_metric=$2
  _expected_names=$3
  shift 3
  if ! PATH="$FAKEBIN:$PATH" "$HELPER" \
    --org example-org --environment alpha --datasource metrics-ds \
    --credential-file "$CRED" --signals "$_test_signals" \
    --acceptance-run "$_valid" "$@" >"$WORKDIR/metric.receipt"; then
    fail "metric receipt invocation failed"
    return
  fi
  _child_metric=$(awk '$0 == "--otlp-metric-name" { getline; print }' "$EMIT_TEST_ARGV")
  if [ "$_child_metric" = "$_expected_metric" ] &&
    grep -Fq "\"metric_names\":$_expected_names" "$WORKDIR/metric.receipt"; then
    pass "child metric name and receipt agree"
  else
    fail "child metric name and receipt disagree"
  fi
}
assert_metric_receipt metrics last9.emit.telemetry '["last9.emit.telemetry","last9_emit_telemetry"]'
assert_metric_receipt metrics custom.test.metric '["custom.test.metric","custom_test_metric"]' \
  --otlp-metric-name custom.test.metric
assert_metric_receipt metrics custom_metric '["custom_metric"]' --otlp-metric-name custom_metric
assert_metric_receipt logs '' '[]' --otlp-metric-name custom.test.metric
assert_metric_receipt traces '' '[]' --otlp-metric-name custom.test.metric

# Signal-specific SDK headers override generic headers. The credential file
# must win over an unrelated parent process's exporter configuration.
cat >"$FAKEBIN/telemetrygen" <<'EOF'
#!/bin/sh
case "$1" in
  metrics) actual=${OTEL_EXPORTER_OTLP_METRICS_HEADERS:-$OTEL_EXPORTER_OTLP_HEADERS} ;;
  logs) actual=${OTEL_EXPORTER_OTLP_LOGS_HEADERS:-$OTEL_EXPORTER_OTLP_HEADERS} ;;
  traces) actual=${OTEL_EXPORTER_OTLP_TRACES_HEADERS:-$OTEL_EXPORTER_OTLP_HEADERS} ;;
esac
# SDK diagnostics may include a bare or decoded value without a header name.
echo 'example-secret-marker' >&2
[ "$actual" = 'Authorization=Basic <your-api-key>' ] || exit 42
EOF
OTEL_EXPORTER_OTLP_METRICS_HEADERS='wrong-org' \
OTEL_EXPORTER_OTLP_LOGS_HEADERS='wrong-org' \
OTEL_EXPORTER_OTLP_TRACES_HEADERS='wrong-org' \
PATH="$FAKEBIN:$PATH" "$HELPER" \
  --org example-org --environment alpha --datasource metrics-ds \
  --credential-file "$CRED" --signals metrics,logs,traces \
  --acceptance-run "$_valid" >"$WORKDIR/isolated.out" 2>"$WORKDIR/isolated.err" && _isolation_st=0 || _isolation_st=$?
if [ "$_isolation_st" -ne 0 ]; then
  fail "ambient signal headers overrode authorized credentials"
else
  pass "authorized credential file wins for every signal"
fi
if grep -q 'example-secret-marker' "$WORKDIR/isolated.err"; then
  fail "raw generator diagnostic leaked"
else
  pass "raw generator diagnostics stay private"
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
python3 "$ROOT_DIR/scripts/last9-emit-telemetry-deadline-selftest.py"
echo "last9-emit-telemetry selftests passed"
