#!/bin/bash

CWD="$(dirname $0)"
DAMSEL="${CWD}/../../damsel"

[ -f woorlrc ] && source woorlrc

SCRIPTNAME=$(basename $0)

get_explanation () {
    "${WOORL[@]:-woorl}" \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/invoicing" \
        Invoicing GetExplanationForChosenRoute "$1" "$2"
}

case "$1" in
    ""|"-h"|"--help" )
        echo -e "Get explanation for routes that was chosen and not chosen in InvoicePayment."
        echo
        echo -e "Usage: ${SCRIPTNAME} invoice_id payment_id [woorl_opts]"
        echo -e "  invoice_id      Invoice ID (string)."
        echo -e "  payment_id      InvoicePayment ID (string)."
        echo -e "  -h, --help      Show this help message."
        echo
        echo -e "More information:"
        echo -e "  https://github.com/valitydev/damsel/blob/3df747ff446bdaac8f136faeb75aa3da65281171/proto/payment_processing.thrift#L1055-L1063"
        exit 0
        ;;
    * )
        INVOICE_ID="\"$1\""
        PAYMENT_ID="\"$2\""
        shift 1
        get_explanation "$INVOICE_ID" "$PAYMENT_ID"
        ;;
esac
