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

[ -f woorlrc ] && source woorlrc

PORT="${PORT:-8022}"
HELLGATE="${HELLGATE:-hellgate}"

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
        printf '%s\n' "${raw}" | jq .
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
        }'
}

raw=$("${WOORL[@]:-woorl}" \
    -s "${DAMSEL}/proto/payment_processing.thrift" \
    "http://${HELLGATE}:${PORT}/v1/processing/invoicing" \
    Invoicing ExplainRoute "\"${INVOICE_ID}\"" "\"${PAYMENT_ID}\"") \
    || err "ExplainRoute request failed for ${INVOICE_ID} / ${PAYMENT_ID}."

emit_explanation "${raw}"
