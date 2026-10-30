#!/usr/bin/env sh
# Wrap telemetrygen so Last9 OTLP test emits never print exporter headers
# or accept plaintext credentials on the command line.
#
# Source with LAST9_EMIT_TELEMETRY_LIB=1 to load helpers without running main.
set -eu
set +x

# Credential-shaped generator/config output. Match broadly so header dumps
# cannot leak via stdout or stderr; callers get sanitized success/failure.
SECRET_LINE_PATTERN='header|authorization|www-authenticate|otlp-header|OTEL_EXPORTER_OTLP_HEADERS|OTLP_HEADERS'
SECRET_VALUE_PATTERN='(^|[^A-Za-z0-9_])(Basic[[:space:]]+[A-Za-z0-9+/=]{8,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{8,})'

is_uuid() {
  printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

new_acceptance_run_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  python3 -c 'import uuid; print(uuid.uuid4())'
}

require_acceptance_run() {
  _run="${1-}"
  if [ -z "$_run" ]; then
    echo "acceptance_run is required" >&2
    return 1
  fi
  if ! is_uuid "$_run"; then
    echo "acceptance_run must be a UUID" >&2
    return 1
  fi
  printf '%s' "$_run"
}

normalize_otlp_endpoint() {
  _raw="${1-}"
  if [ -z "$_raw" ]; then
    echo "OTLP endpoint is empty" >&2
    return 1
  fi
  _norm=$(printf '%s' "$_raw" | awk '{
    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
    sub(/^[Hh][Tt][Tt][Pp][Ss]:\/\//, "")
    sub(/^[Hh][Tt][Tt][Pp]:\/\//, "")
    gsub(/\/+$/, "")
    if (match($0, /^[^\/]+/)) $0 = substr($0, 1, RLENGTH)
    print
  }')
  if [ -z "$_norm" ]; then
    echo "OTLP endpoint normalized to empty" >&2
    return 1
  fi
  case "$_norm" in
    *@*)
      echo "OTLP endpoint must not include userinfo" >&2
      return 1
      ;;
  esac
  printf '%s' "$_norm"
}

is_safe_id() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._:+=@-]+$'
}

json_quote() {
  printf '"'
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  printf '"'
}

# Fail closed: if credential-shaped text is present, drop the whole buffer.
sanitize_exporter_output() {
  _buf=$(cat)
  if printf '%s' "$_buf" | grep -qiE "$SECRET_LINE_PATTERN"; then
    echo "generator logs suppressed (credential-shaped content)" >&2
    return 0
  fi
  if printf '%s' "$_buf" | grep -qiE "$SECRET_VALUE_PATTERN"; then
    echo "generator logs suppressed (credential-shaped content)" >&2
    return 0
  fi
  printf '%s' "$_buf"
  [ -n "$_buf" ] && printf '\n'
  return 0
}

output_contains_exporter_headers() {
  if printf '%s' "${1-}" | grep -qiE "$SECRET_LINE_PATTERN"; then
    return 0
  fi
  if printf '%s' "${1-}" | grep -qiE "$SECRET_VALUE_PATTERN"; then
    return 0
  fi
  return 1
}

receipt_forbidden_keys() {
  printf '%s\n' headers authorization token password credential otlp-header OTEL_EXPORTER_OTLP_HEADERS OTLP_HEADERS
}

receipt_contains_forbidden() {
  _json="${1-}"
  _hit=1
  for _k in $(receipt_forbidden_keys); do
    if printf '%s' "$_json" | grep -q "\"$_k\""; then
      _hit=0
      break
    fi
  done
  if output_contains_exporter_headers "$_json"; then
    _hit=0
  fi
  return "$_hit"
}

build_receipt() {
  _run="$1"
  _org="$2"
  _env="$3"
  _signals="$4"
  _metrics="$5"
  _service="$6"
  _started="$7"
  _ended="$8"
  _datasource="$9"
  _export="${10}"
  _queryable="${11}"
  printf '{'
  printf '"acceptance_run":%s,' "$(json_quote "$_run")"
  printf '"org":%s,' "$(json_quote "$_org")"
  printf '"environment":%s,' "$(json_quote "$_env")"
  printf '"signal_types":%s,' "$_signals"
  printf '"metric_names":%s,' "$_metrics"
  printf '"service_name":%s,' "$(json_quote "$_service")"
  printf '"started_at":%s,' "$(json_quote "$_started")"
  printf '"ended_at":%s,' "$(json_quote "$_ended")"
  printf '"datasource":%s,' "$(json_quote "$_datasource")"
  printf '"otlp_export":%s,' "$(json_quote "$_export")"
  printf '"last9_queryable":%s' "$(json_quote "$_queryable")"
  printf '}\n'
}

quoted_attr() {
  printf '%s="%s"' "$1" "$2"
}

# Prints argv one flag/value per line. Never includes headers or env values.
build_telemetrygen_argv() {
  _signal="$1"
  _endpoint="$2"
  _service="$3"
  _run="$4"
  _duration="$5"
  _rate="$6"
  _workers="$7"
  _metric_name="$8"
  _insecure="$9"

  printf '%s\n' telemetrygen "$_signal"
  printf '%s\n' --otlp-endpoint "$_endpoint"
  printf '%s\n' --duration "$_duration" --rate "$_rate" --workers "$_workers"
  printf '%s\n' --service "$_service"
  printf '%s\n' --otlp-attributes "$(quoted_attr service.name "$_service")"
  printf '%s\n' --otlp-attributes "$(quoted_attr acceptance_run "$_run")"
  printf '%s\n' --telemetry-attributes "$(quoted_attr acceptance_run "$_run")"
  if [ "$_signal" = "metrics" ]; then
    printf '%s\n' --otlp-metric-name "$_metric_name"
  fi
  if [ "$_insecure" = "1" ]; then
    printf '%s\n' --otlp-insecure
  fi
}

argv_contains_header_flags() {
  printf '%s\n' "$@" | grep -qiE -- '--otlp-header|^-otlp-header$|Authorization=|OTEL_EXPORTER_OTLP_HEADERS'
}

load_credential_file() {
  # Sets _cred_endpoint and _cred_headers in the caller. Never prints values.
  _file="$1"
  _cred_endpoint=""
  _cred_headers=""
  if [ -z "$_file" ] || [ ! -f "$_file" ] || [ ! -r "$_file" ]; then
    echo "credential file not found or not readable" >&2
    return 1
  fi
  while IFS= read -r _line || [ -n "${_line-}" ]; do
    case "$_line" in
      ''|\#*) continue ;;
      OTEL_EXPORTER_OTLP_ENDPOINT=*|OTLP_ENDPOINT=*)
        _cred_endpoint=${_line#*=}
        _cred_endpoint=${_cred_endpoint#\"}
        _cred_endpoint=${_cred_endpoint%\"}
        _cred_endpoint=${_cred_endpoint#\'}
        _cred_endpoint=${_cred_endpoint%\'}
        ;;
      OTEL_EXPORTER_OTLP_HEADERS=*|OTLP_HEADERS=*)
        _cred_headers=${_line#*=}
        _cred_headers=${_cred_headers#\"}
        _cred_headers=${_cred_headers%\"}
        _cred_headers=${_cred_headers#\'}
        _cred_headers=${_cred_headers%\'}
        ;;
      *)
        ;;
    esac
  done < "$_file"
  if [ -z "$_cred_endpoint" ] || [ -z "$_cred_headers" ]; then
    echo "credential file must set an endpoint key and a headers key" >&2
    return 1
  fi
}

credential_ref_looks_like_secret() {
  _ref="${1-}"
  [ -n "$_ref" ] || return 1
  case "$_ref" in
    Authorization=*|Basic\ *|Bearer\ *) return 0 ;;
  esac
  printf '%s' "$_ref" | grep -qiE "$SECRET_VALUE_PATTERN"
}

signals_json_array() {
  _first=1
  printf '['
  for _s in $(printf '%s' "$1" | tr ',' ' '); do
    [ -n "$_s" ] || continue
    if [ "$_first" -eq 1 ]; then
      _first=0
    else
      printf ','
    fi
    json_quote "$_s"
  done
  printf ']'
}

metric_names_json_array() {
  case ",$1," in
    *,metrics,*)
      printf '[%s,%s]' "$(json_quote last9.emit.telemetry)" "$(json_quote last9_emit_telemetry)"
      ;;
    *)
      printf '[]'
      ;;
  esac
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

host_is_local() {
  case "$1" in
    localhost|localhost:*|127.0.0.1|127.0.0.1:*) return 0 ;;
  esac
  return 1
}

last9_emit_telemetry_usage() {
  cat <<'EOF'
Usage: last9-emit-telemetry.sh --org <org-slug> --environment <env> --datasource <id> (--credential-file <path> | --credential-env <VAR>) [--signals metrics,logs,traces]

Never pass plaintext credentials. --credential-file / --credential-env must name a local file.
EOF
}

last9_emit_telemetry_main() {
  _org=""
  _environment=""
  _datasource=""
  _cred_file=""
  _cred_env=""
  _signals="metrics,logs,traces"
  _service="last9-emit-telemetry"
  _duration="5s"
  _rate="1"
  _workers="1"
  _run=""
  _run_set=0
  _metric_name="last9.emit.telemetry"
  _print_argv=0
  _dry_run=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --org) _org=$2; shift 2 ;;
      --environment) _environment=$2; shift 2 ;;
      --datasource) _datasource=$2; shift 2 ;;
      --credential-file) _cred_file=$2; shift 2 ;;
      --credential-env) _cred_env=$2; shift 2 ;;
      --signals) _signals=$2; shift 2 ;;
      --service) _service=$2; shift 2 ;;
      --duration) _duration=$2; shift 2 ;;
      --rate) _rate=$2; shift 2 ;;
      --workers) _workers=$2; shift 2 ;;
      --acceptance-run) _run=$2; _run_set=1; shift 2 ;;
      --otlp-metric-name) _metric_name=$2; shift 2 ;;
      --print-argv) _print_argv=1; shift ;;
      --dry-run) _dry_run=1; shift ;;
      -h|--help) last9_emit_telemetry_usage; return 0 ;;
      --otlp-header|--header)
        echo "refusing --otlp-header; pass a credential file reference instead" >&2
        return 1
        ;;
      *)
        echo "unknown argument: $1" >&2
        last9_emit_telemetry_usage >&2
        return 1
        ;;
    esac
  done

  if [ -z "$_org" ] || [ -z "$_environment" ] || [ -z "$_datasource" ]; then
    echo "org, environment, and datasource are required" >&2
    return 1
  fi
  for _id in "$_org" "$_environment" "$_datasource" "$_service" "$_metric_name"; do
    if ! is_safe_id "$_id"; then
      echo "org, environment, datasource, service, and metric name must be simple identifiers" >&2
      return 1
    fi
  done

  case "$_duration" in
    inf|INF|0|0s|"")
      echo "duration must be a short finite bound (default 5s)" >&2
      return 1
      ;;
  esac
  case "$_rate" in
    0|"")
      echo "rate 0 is unlimited; refusing" >&2
      return 1
      ;;
  esac

  if [ "$_run_set" -eq 1 ]; then
    require_acceptance_run "$_run" >/dev/null || return 1
  else
    _run=$(new_acceptance_run_id) || return 1
    require_acceptance_run "$_run" >/dev/null || return 1
  fi

  if [ -n "$_cred_env" ]; then
    if ! printf '%s' "$_cred_env" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
      echo "credential env must be a variable name, not a value" >&2
      return 1
    fi
    eval "_cred_file=\${$_cred_env-}"
    if credential_ref_looks_like_secret "$_cred_file"; then
      echo "credential env must hold a file path, not a secret" >&2
      return 1
    fi
  fi
  if credential_ref_looks_like_secret "$_cred_file"; then
    echo "credential file must be a path, not a secret" >&2
    return 1
  fi
  if [ -z "$_cred_file" ]; then
    echo "pass --credential-file or --credential-env naming a local file" >&2
    return 1
  fi

  load_credential_file "$_cred_file" || return 1
  _endpoint=$(normalize_otlp_endpoint "$_cred_endpoint") || return 1
  _insecure=0
  if host_is_local "$_endpoint"; then
    _insecure=1
  fi

  _started=$(utc_now)
  _export="not_executed"
  _any_fail=0

  for _signal in $(printf '%s' "$_signals" | tr ',' ' '); do
    case "$_signal" in
      metrics|logs|traces) ;;
      *) echo "unknown signal: $_signal" >&2; return 1 ;;
    esac
    _argv_file=$(mktemp "${TMPDIR:-/tmp}/last9-emit-argv.XXXXXX")
    build_telemetrygen_argv "$_signal" "$_endpoint" "$_service" "$_run" \
      "$_duration" "$_rate" "$_workers" "$_metric_name" "$_insecure" >"$_argv_file"
    if grep -qiE -- '--otlp-header|Authorization=|OTEL_EXPORTER_OTLP_HEADERS' "$_argv_file"; then
      rm -f "$_argv_file"
      echo "internal error: constructed argv included exporter headers" >&2
      return 1
    fi
    if [ "$_print_argv" -eq 1 ]; then
      tr '\n' ' ' <"$_argv_file"
      printf '\n'
      rm -f "$_argv_file"
      continue
    fi
    if [ "$_dry_run" -eq 1 ]; then
      rm -f "$_argv_file"
      continue
    fi
    if ! command -v telemetrygen >/dev/null 2>&1; then
      rm -f "$_argv_file"
      echo "telemetrygen not on PATH" >&2
      return 1
    fi
    _out=$(mktemp "${TMPDIR:-/tmp}/last9-emit-out.XXXXXX")
    _err=$(mktemp "${TMPDIR:-/tmp}/last9-emit-err.XXXXXX")
    _cmd_bin=""
    set --
    while IFS= read -r _tok || [ -n "${_tok-}" ]; do
      if [ -z "$_cmd_bin" ]; then
        _cmd_bin=$_tok
        continue
      fi
      set -- "$@" "$_tok"
    done < "$_argv_file"
    set +e
    (
      set +x
      export OTEL_EXPORTER_OTLP_HEADERS="$_cred_headers"
      # Headers stay in the child environment, never on argv / process listing.
      "$_cmd_bin" "$@" >"$_out" 2>"$_err"
    )
    _st=$?
    set -e
    rm -f "$_argv_file"
    sanitize_exporter_output <"$_out" >/dev/null
    sanitize_exporter_output <"$_err" >&2
    rm -f "$_out" "$_err"
    if [ "$_st" -ne 0 ]; then
      _any_fail=1
    fi
  done

  unset _cred_headers
  unset OTEL_EXPORTER_OTLP_HEADERS 2>/dev/null || true

  if [ "$_print_argv" -eq 1 ]; then
    return 0
  fi
  if [ "$_dry_run" -eq 1 ]; then
    _export="not_executed"
  elif [ "$_any_fail" -eq 0 ]; then
    _export="client_ok"
  else
    _export="client_failed"
  fi
  _ended=$(utc_now)
  _receipt=$(build_receipt "$_run" "$_org" "$_environment" \
    "$(signals_json_array "$_signals")" "$(metric_names_json_array "$_signals")" \
    "$_service" "$_started" "$_ended" "$_datasource" "$_export" "no")
  if receipt_contains_forbidden "$_receipt"; then
    echo "receipt redaction failed; refusing to print" >&2
    return 1
  fi
  printf '%s\n' "$_receipt"
  if [ "$_any_fail" -ne 0 ]; then
    return 1
  fi
  return 0
}

if [ "${LAST9_EMIT_TELEMETRY_LIB:-0}" != "1" ]; then
  last9_emit_telemetry_main "$@"
fi
