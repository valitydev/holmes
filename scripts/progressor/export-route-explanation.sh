#!/bin/bash

set -o errexit
set -o pipefail

CWD="$(dirname "$0")"
SCRIPTNAME="$(basename "$0")"
DAMSEL="${CWD}/../../damsel"

source "${CWD}/../lib/logging"

USAGE=$(cat <<EOF
Export ExplainRoute as one JSON document for the Mattermost route viewer.

Usage: ${SCRIPTNAME} INVOICE_ID PAYMENT_ID

  Botkube / bg-prod-bot (same pattern as export-trace.sh):
    bash -c 'HELLGATE=hellgate.default ./scripts/progressor/export-route-explanation.sh 2L4zRGVWsGO 1'

  Redirect stdout to a .json file if you save traces locally:
    ${SCRIPTNAME} 2L4zRGVWsGO 1 > 2L4zRGVWsGO.route.json

  Only stdout is the attachment body (response.txt). Errors go to stderr.
  ExplainRoute JSON is small; stdout is padded so Botkube uploads response.txt
  (Mattermost inline limit is 3990 bytes in Botkube).

Environment:
  HELLGATE     Hellgate host (default: hellgate)
  PORT         Woody port (default: 8022)

  -h, --help   Show this help message.
EOF
)

function usage {
    echo "${USAGE}"
    exit "${1:-127}"
}

command -v jq >/dev/null 2>&1 || err "jq is required."

case "${1:-}" in
    ""|"-h"|"--help" )
        usage 0
        ;;
esac

INVOICE_ID="${1:-}"
PAYMENT_ID="${2:-}"
[ -z "${INVOICE_ID}" ] || [ -z "${PAYMENT_ID}" ] && usage 127
[ "$#" -gt 2 ] && usage 127

HOLMES_ROOT="$(cd "${CWD}/../.." && pwd)"
[ -f "${HOLMES_ROOT}/woorlrc" ] && source "${HOLMES_ROOT}/woorlrc"

PORT="${PORT:-8022}"
HELLGATE="${HELLGATE:-hellgate}"

# kubeshop/botkube pkg/bot/mattermost.go mattermostMaxMessageSize
BOTKUBE_MATTERMOST_FILE_THRESHOLD=3990

function ensure_botkube_file_upload {
    local json size need pad
    json=$(cat)
    size=${#json}
    if [ "${size}" -ge "${BOTKUBE_MATTERMOST_FILE_THRESHOLD}" ]; then
        printf '%s\n' "${json}"
        return
    fi
    need=$((BOTKUBE_MATTERMOST_FILE_THRESHOLD - size + 64))
    pad=$(printf '%*s' "${need}" '')
    printf '%s\n' "${json}" | jq --arg pad "${pad}" '. + {_botkube_file_padding: $pad}'
}

function is_route_not_chosen {
    local raw="$1"
    printf '%s\n' "${raw}" | jq -e '
        (.exception == "RouteNotChosen")
        or ((.exception | type) == "object" and (.exception | has("RouteNotChosen")))
    ' >/dev/null 2>&1
}

function woorl_failure_message {
    local raw="$1"
    printf '%s\n' "${raw}" | jq -r '
        if (.exception | type) == "object" then
            (.exception | to_entries[0] | "\(.key): \(.value)")
        elif (.exception | type) == "string" then
            .exception
        else
            empty
        end
    ' 2>/dev/null || true
}

function emit_explanation {
    local raw="$1"
    if ! printf '%s\n' "${raw}" | jq -e 'type == "object"' >/dev/null 2>&1; then
        err "ExplainRoute did not return JSON."
    fi
    if is_route_not_chosen "${raw}"; then
        printf '%s\n' "${raw}" | jq . | ensure_botkube_file_upload
        return 0
    fi
    local failure
    failure=$(woorl_failure_message "${raw}")
    if [ -n "${failure}" ]; then
        err "ExplainRoute failed: ${failure}"
    fi
    if ! printf '%s\n' "${raw}" | jq -e 'has("explained_routes") or has("used_varset")' >/dev/null 2>&1; then
        err "ExplainRoute did not return InvoicePaymentExplanation JSON."
    fi
    printf '%s\n' "${raw}" | jq \
        --arg invoice_id "${INVOICE_ID}" \
        --arg payment_id "${PAYMENT_ID}" \
        '. + {
            meta: {
                kind: "route_explanation",
                invoice_id: $invoice_id,
                payment_id: $payment_id
            }
        }' | ensure_botkube_file_upload
}

raw=$("${WOORL[@]:-woorl}" \
    -s "${DAMSEL}/proto/payment_processing.thrift" \
    "http://${HELLGATE}:${PORT}/v1/processing/invoicing" \
    Invoicing ExplainRoute "\"${INVOICE_ID}\"" "\"${PAYMENT_ID}\"") \
    || err "ExplainRoute request failed for ${INVOICE_ID} / ${PAYMENT_ID}."

emit_explanation "${raw}"
