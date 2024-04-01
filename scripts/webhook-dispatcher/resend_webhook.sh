#!/bin/bash

CWD="$(dirname "$0")"
WEBHOOK_DISPATCHER_PROTO="${CWD}/../../webhook-dispatcher-proto"

[ -f woorlrc ] && source woorlrc

SCRIPT_NAME=$(basename "$0")

resend_webhook () {
    "${WOORL[@]:-woorl}" \
        -s "${WEBHOOK_DISPATCHER_PROTO}/proto/webhook_dispatcher.thrift" \
        "http://${WEBHOOK_DISPATCHER:-webhook-dispatcher}:8022/webhook-message-service" \
        WebhookMessageService Resend "$1" "$2" "$3"
}

case "$1" in
    ""|"-h"|"--help" )
        echo -e "Trying to resend failed webhook given WebhookID, SourceID and EventId."
        echo
        echo -e "Usage: ${SCRIPT_NAME} webhook_id source_id event_id [woorl_opts]"
        echo -e "  webhook_id      Webhook ID (number)."
        echo -e "  source_id       Source ID (string)."
        echo -e "  event_id        Event ID (number)."
        echo -e "  -h, --help      Show this help message."
        echo
        echo -e "More information:"
        echo -e "  https://github.com/valitydev/webhook-dispatcher-proto/blob/master/proto/webhook_dispatcher.thrift#L28C85-L28C93"
        exit 0
        ;;
    * )
        WEBHOOK_ID="{$1}"
        SOURCE_ID="\"$2\""
        EVENT_ID="{$3}"
        resend_webhook "$WEBHOOK_ID" "$SOURCE_ID" "$EVENT_ID"
        ;;
esac