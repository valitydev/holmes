#!/bin/bash

set -e

CWD="$(dirname $0)"
DAMSEL="${CWD}/../../damsel"

[ -f woorlrc ] && source woorlrc

SCRIPTNAME=$(basename $0)

source "${CWD}/../lib/logging"

usage () {
    echo -e "Given ID of an invoice fetch a number of events emitted by this invoice."
    echo
    echo -e "Usage: $(em ${SCRIPTNAME} invoice_id payment_id chargeback_id)"
    echo -e "  $(em invoice_id)      Invoice ID (string)."
    echo -e "  $(em payment_id)      Payment ID (string)."
    echo -e "  $(em chargeback_id)   Chargeback ID (string)."
    echo -e "  -h, --help            Show this help message."
    echo
    echo -e "More information:"
    echo -e "  https://github.com/valitydev/damsel/blob/ecf49770668a5985e0cb2989220318d205e14c37/proto/payment_processing.thrift#L1318-L1335"
    echo -e "  https://github.com/valitydev/damsel/blob/ecf49770668a5985e0cb2989220318d205e14c37/proto/payment_processing.thrift#L1340-L1352"
    exit 127
}

reopen_chargeback() {
    "${WOORL[@]:-woorl}" \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/invoicing" \
        Invoicing ReopenChargeback "$1" "$2" "$3" "{}"
}

cancel_chargeback() {
    "${WOORL[@]:-woorl}" \
        -s "${DAMSEL}/proto/payment_processing.thrift" \
        "http://${HELLGATE:-hellgate}:8022/v1/processing/invoicing" \
        Invoicing CancelChargeback "$1" "$2" "$3" "{}"
}

case "$1" in
    ""|"-h"|"--help" )
        usage
        ;;
    * )
        INVOICE_ID="\"$1\""
        PAYMENT_ID="\"$2\""
        CHARGEBACK_ID="\"$3\""
        reopen_chargeback "$INVOICE_ID" "$PAYMENT_ID" "$CHARGEBACK_ID"
        echo -n "Chargeback $CHARGEBACK_ID $(info reopened)."
        cancel_chargeback "$INVOICE_ID" "$PAYMENT_ID" "$CHARGEBACK_ID"
        echo -n "Chargeback $CHARGEBACK_ID $(info canceled)."
        echo -n "$(info Done.)"
        ;;
esac
