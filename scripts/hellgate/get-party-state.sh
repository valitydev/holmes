#!/bin/bash

CWD="$(dirname $0)"
DAMSEL="${CWD}/../../damsel"

[ -f woorlrc ] && source woorlrc

SCRIPTNAME=$(basename $0)

get_party () {
    "${WOORL[@]:-woorl}" $2 \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/partymgmt" \
        PartyManagement Get "$1"
}

case "$1" in
    ""|"-h"|"--help" )
        echo -e "Fetch state of a party given its ID."
        echo
        echo -e "Usage: ${SCRIPTNAME} party_id [woorl_opts]"
        echo -e "  party_id        Party ID (string)."
        echo -e "  -h, --help      Show this help message."
        echo
        echo -e "More information:"
        echo -e "  https://github.com/valitydev/damsel/blob/2e1dbc1a/proto/payment_processing.thrift#L2494-L2495"
        exit 0
        ;;
    * )
        PARTY_ID="\"$1\""
        shift 1
        get_party "$PARTY_ID" "$*"
        ;;
esac
