#!/bin/bash

CWD="$(dirname $0)"
SCRIPTNAME="$(basename $0)"
DAMSEL="${CWD}/../../damsel"
FISTFUL_PROTO="${CWD}/../../fistful-proto"

source "${CWD}/../lib/logging"

USAGE=$(cat <<EOF
Export a progressor process trace as one JSON document for the Mattermost viewer.

Usage: ${SCRIPTNAME} KIND PROCESS_ID
  KIND         Process kind (see table below).
  PROCESS_ID   Process / machine ID (string).

  Redirect stdout to KIND.trace.json so Mattermost will preview the file:
    ${SCRIPTNAME} invoice 2EFarPpHptQ > invoice.trace.json
    ${SCRIPTNAME} withdrawal Wd1 > withdrawal.trace.json

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

case "$1" in
    "" )
        usage 127
        ;;
    "-h"|"--help" )
        usage 0
        ;;
esac

KIND="$1"
PROCESS_ID="$2"
[ -z "${PROCESS_ID}" ] && usage 127

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

RAW=$("${WOORL[@]:-woorl}" \
    -s "${PROTO}" \
    "http://${HOST}:${PORT}/v1/trace" \
    Trace GetTrace "\"${NAMESPACE}\"" "\"${PROCESS_ID}\"") \
    || err "GetTrace request failed."

if ! echo "${RAW}" | jq -e 'type == "array"' >/dev/null 2>&1; then
    EX=$(echo "${RAW}" | jq -r '
        if type == "object" and has("exception") then
            .exception | tostring
        else
            empty
        end
    ' 2>/dev/null || true)
    if [ -n "${EX}" ]; then
        err "GetTrace failed: ${EX}"
    else
        err "GetTrace did not return a JSON array of trace units."
    fi
fi

echo "${RAW}" | jq \
    --arg backend "${BACKEND}" \
    --arg namespace "${NAMESPACE}" \
    --arg process_id "${PROCESS_ID}" \
    -f "${CWD}/wrap-trace.jq"
