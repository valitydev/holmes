#!/bin/bash

CWD="$(dirname $0)"
DAMSEL="${CWD}/../../damsel"

[ -f woorlrc ] && source woorlrc

SCRIPTNAME=$(basename $0)

get_limit_values () {
    "${WOORL[@]:-woorl}" \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/invoicing" \
        Invoicing GetPaymentRoutesLimitValues "$1" "$2"
}

case "$1" in
    ""|"-h"|"--help" )
        echo -e "Fetch routes limit values given InvoiceID and PaymentID."
        echo
        echo -e "Usage: ${SCRIPTNAME} invoice_id payment_id [woorl_opts]"
        echo -e "  invoice_id      Invoice ID (string)."
        echo -e "  payment_id      Payment ID (string)."
        echo -e "  -h, --help      Show this help message."
        echo
        echo -e "More information:"
        echo -e "  https://github.com/valitydev/damsel/blob/2e1dbc1a/proto/payment_processing.thrift#L1518-L1523"
        exit 0
        ;;
    * )
        INVOICE_ID="\"$1\""
        PAYMENT_ID="\"$2\""
        get_limit_values "$INVOICE_ID" "$PAYMENT_ID"
        ;;
esac
