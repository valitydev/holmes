#!/bin/bash

CWD="$(dirname $0)"
SCRIPTNAME="$(basename $0)"
DAMSEL="${CWD}/../../damsel"
FISTFUL_PROTO="${CWD}/../../fistful-proto"

source "${CWD}/../lib/logging"

USAGE=$(cat <<EOF
Export a progressor process trace as one JSON document for the Mattermost viewer.

Usage: ${SCRIPTNAME} [--no-sessions] KIND PROCESS_ID
  KIND         Process kind (see table below).
  PROCESS_ID   Process / machine ID (string).

  Redirect stdout to KIND.trace.json so Mattermost will preview the file:
    ${SCRIPTNAME} invoice 2EFarPpHptQ > invoice.trace.json
    ${SCRIPTNAME} withdrawal Wd1 > withdrawal.trace.json

  For withdrawal, each session machine referenced by a session change is
  fetched too (ff/withdrawal/session_v2) and stored in related[]. One
  withdrawal, many sessions. schema_version stays 1, so the current
  viewer still opens the withdrawal trace. A failed session GetTrace
  fails the whole export.

  --no-sessions
               Do not fetch session machines. The withdrawal file is only
               the parent trace, with no related field. Ignored for other kinds.

  KIND                 namespace                    proto           host env
  invoice              invoice                      damsel          HELLGATE
  invoice_template     invoice_template             damsel          HELLGATE
  withdrawal           ff/withdrawal_v2             fistful-proto   FISTFUL
  deposit              ff/deposit_v1                fistful-proto   FISTFUL
  destination          ff/destination_v2            fistful-proto   FISTFUL
  source               ff/source_v1                 fistful-proto   FISTFUL
  session              ff/withdrawal/session_v2     fistful-proto   FISTFUL

Environment:
  HELLGATE     Host for damsel kinds (default: hellgate)
  FISTFUL      Host for fistful kinds (default: fistful_server)
  PORT         Woody port (default: 8022)

  -h, --help   Show this help message.
EOF
)

function usage {
    echo "${USAGE}"
    exit "${1:-127}"
}

command -v jq >/dev/null 2>&1 || err "jq is required."

NO_SESSIONS=0
POSITIONAL=()
for ARG in "$@"; do
    case "${ARG}" in
        "" )
            usage 127
            ;;
        "-h"|"--help" )
            usage 0
            ;;
        "--no-sessions" )
            NO_SESSIONS=1
            ;;
        * )
            POSITIONAL+=("${ARG}")
            ;;
    esac
done

KIND="${POSITIONAL[0]:-}"
PROCESS_ID="${POSITIONAL[1]:-}"
[ -z "${KIND}" ] && usage 127
[ -z "${PROCESS_ID}" ] && usage 127
[ "${#POSITIONAL[@]}" -gt 2 ] && usage 127

case "${KIND}" in
    invoice )
        BACKEND="hg"
        NAMESPACE="invoice"
        PROTO="${DAMSEL}/proto/progressor_trace.thrift"
        HOST="${HELLGATE:-hellgate}"
        ;;
    invoice_template )
        BACKEND="hg"
        NAMESPACE="invoice_template"
        PROTO="${DAMSEL}/proto/progressor_trace.thrift"
        HOST="${HELLGATE:-hellgate}"
        ;;
    withdrawal )
        BACKEND="ff"
        NAMESPACE="ff/withdrawal_v2"
        PROTO="${FISTFUL_PROTO}/proto/progressor_trace.thrift"
        HOST="${FISTFUL:-fistful_server}"
        ;;
    deposit )
        BACKEND="ff"
        NAMESPACE="ff/deposit_v1"
        PROTO="${FISTFUL_PROTO}/proto/progressor_trace.thrift"
        HOST="${FISTFUL:-fistful_server}"
        ;;
    destination )
        BACKEND="ff"
        NAMESPACE="ff/destination_v2"
        PROTO="${FISTFUL_PROTO}/proto/progressor_trace.thrift"
        HOST="${FISTFUL:-fistful_server}"
        ;;
    source )
        BACKEND="ff"
        NAMESPACE="ff/source_v1"
        PROTO="${FISTFUL_PROTO}/proto/progressor_trace.thrift"
        HOST="${FISTFUL:-fistful_server}"
        ;;
    session )
        BACKEND="ff"
        NAMESPACE="ff/withdrawal/session_v2"
        PROTO="${FISTFUL_PROTO}/proto/progressor_trace.thrift"
        HOST="${FISTFUL:-fistful_server}"
        ;;
    * )
        err "Unknown kind: ${KIND}"
        ;;
esac

[ -f woorlrc ] && source woorlrc

PORT="${PORT:-8022}"
SESSION_NAMESPACE="ff/withdrawal/session_v2"

# err exits the shell. Call these in the main shell, not from a pipeline or $().
function require_trace_array {
    local raw="$1"
    local label="$2"
    local ex
    if printf '%s\n' "${raw}" | jq -e 'type == "array"' >/dev/null 2>&1; then
        return 0
    fi
    ex=$(printf '%s\n' "${raw}" | jq -r '
        if type == "object" and has("exception") then
            .exception | tostring
        else
            empty
        end
    ' 2>/dev/null || true)
    if [ -n "${ex}" ]; then
        err "GetTrace failed for ${label}: ${ex}"
    fi
    err "GetTrace did not return a JSON array of trace units (${label})."
}

function fetch_trace_to {
    local ns="$1"
    local id="$2"
    local dest="$3"
    local raw
    raw=$("${WOORL[@]:-woorl}" \
        -s "${PROTO}" \
        "http://${HOST}:${PORT}/v1/trace" \
        Trace GetTrace "\"${ns}\"" "\"${id}\"") \
        || err "GetTrace request failed for ${ns} ${id}."
    require_trace_array "${raw}" "${ns} ${id}"
    printf '%s\n' "${raw}" > "${dest}"
}

function wrap_trace_to {
    local backend="$1"
    local ns="$2"
    local id="$3"
    local src="$4"
    local dest="$5"
    jq \
        --arg backend "${backend}" \
        --arg namespace "${ns}" \
        --arg process_id "${id}" \
        -f "${CWD}/wrap-trace.jq" \
        < "${src}" > "${dest}" \
        || err "Failed to wrap trace for ${ns} ${id}."
}

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/export-trace.XXXXXX")
trap 'rm -rf "${WORKDIR}"' EXIT

fetch_trace_to "${NAMESPACE}" "${PROCESS_ID}" "${WORKDIR}/raw.json"
wrap_trace_to "${BACKEND}" "${NAMESPACE}" "${PROCESS_ID}" "${WORKDIR}/raw.json" "${WORKDIR}/parent.json"

if [ "${KIND}" != "withdrawal" ] || [ "${NO_SESSIONS}" -eq 1 ]; then
    cat "${WORKDIR}/parent.json"
    exit 0
fi

printf '%s\n' '[]' > "${WORKDIR}/related.json"
jq -f "${CWD}/session-ids.jq" "${WORKDIR}/parent.json" > "${WORKDIR}/ids.json" \
    || err "Failed to read session ids from the withdrawal trace."

while IFS= read -r SID; do
    [ -z "${SID}" ] && continue
    fetch_trace_to "${SESSION_NAMESPACE}" "${SID}" "${WORKDIR}/sraw.json"
    wrap_trace_to "${BACKEND}" "${SESSION_NAMESPACE}" "${SID}" "${WORKDIR}/sraw.json" "${WORKDIR}/one.json"
    jq --slurpfile item "${WORKDIR}/one.json" '. + $item' "${WORKDIR}/related.json" > "${WORKDIR}/next.json" \
        || err "Failed to append session ${SID}."
    mv "${WORKDIR}/next.json" "${WORKDIR}/related.json"
done < <(jq -r '.[]' "${WORKDIR}/ids.json")

jq --slurpfile related "${WORKDIR}/related.json" '. + {related: $related[0]}' "${WORKDIR}/parent.json"
