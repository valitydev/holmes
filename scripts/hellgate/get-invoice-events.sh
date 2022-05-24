#!/bin/bash

CWD="$(dirname $0)"
DAMSEL="${CWD}/../../damsel"

[ -f woorlrc ] && source woorlrc

SCRIPTNAME=$(basename $0)

get_events () {
    "${WOORL[@]:-woorl}" \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/invoicing" \
        Invoicing GetEvents "$1" "$2"
}

case "$1" in
    ""|"-h"|"--help" )
        echo -e "Given ID of an invoice fetch a number of events emitted by this invoice."
        echo
        echo -e "Usage: ${SCRIPTNAME} invoice_id [limit] [after] [woorl_opts]"
        echo -e "  invoice_id      Invoice ID (string)."
        echo -e "  limit           Limit of number of events to fetch."
        echo -e "  after           Event ID after which we want to fetch events." \
                                  "Leave it out to fetch events from the very start."
        echo -e "  -h, --help      Show this help message."
        echo
        echo -e "More information:"
        echo -e "  https://github.com/valitydev/damsel/blob/2e1dbc1a/proto/payment_processing.thrift#L1054-L1059"
        exit 0
        ;;
    * )
        INVOICE_ID="\"$1\""
        shift 1
        if [ -n "$1" ]; then
            LIMIT=$1
            shift 1
        else
            LIMIT=100
        fi
        shift 1
        if [ -n "$1" ]; then
            RANGE="{\"after\":$1,\"limit\":${LIMIT}}"
            shift 1
        else
            RANGE="{\"limit\":${LIMIT}}"
        fi
        get_events "$INVOICE_ID" "$RANGE"
        ;;
esac
