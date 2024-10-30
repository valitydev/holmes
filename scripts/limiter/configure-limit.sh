#!/bin/bash

set -o errexit
set -o pipefail

CWD="$(dirname "$0")"
SCRIPTNAME=$(basename "$0")
LIMITER_PROTO="${CWD}/../../limiter-proto"

ln -s "$(realpath "${CWD}/../../damsel/proto")" "${LIMITER_PROTO}/proto/proto"
trap "rm -rf ${LIMITER_PROTO}/proto/proto" EXIT

source "${CWD}/../lib/logging"

USAGE=$(cat <<EOF
$(em Create configuration usage in limit counting.)
Usage: ${SCRIPTNAME} --time-range=<range> [--scope=<scope>] [--turnover-metric=<metric>] [--currency=<code>] [--subtraction] [--shard-size=<size>] <id> <started-at> <description>
  $(em id)                        Limit config ID (string)
  $(em started-at)                Timestamp (RFC3339) Example: 2021-07-06T01:02:03Z
  $(em description)               Limit description (string)
  $(em --time-range)              Specify calendar time range ($(em day) | $(em week) | $(em month) | $(em year))
  $(em --context)                 Specify limit context type ($(em payproc) | $(em withdrawal))
  $(em --scope)                   Specify limit scope ($(em party) | $(em shop) | $(em paytool) | $(em wallet) | $(em identity) | $(em provider) | $(em terminal) | $(em email)) [default: global scope]
                                   - Multiple scopes are allowed.
  $(em --turnover-metric)         Select turnover metric ($(em number) | $(em amount))
                                   - Metric $(em amount) aggregates operations' amounts denominated in selected currency. [default]
                                   - Metric $(em number) counts number of operations.
  $(em --currency)                Set currency for the $(em amount) turnover metric (ISO 4217). [default: $(em RUB)]
  $(em --subtraction)             Limiter behaviour when process payment refund. After refund limit will decrease on refund amount.
  $(em --shard-size)              Specify shard size [default: 1]

More information:
  https://github.com/valitydev/limiter-proto/blob/master/proto/configurator.thrift
EOF
)

function usage {
    echo -e "$USAGE"
    exit 127
}

TEMP=$(getopt -o "" --longoptions help,time-range:,context:,scope:,turnover-metric:,currency:,subtraction -n "$SCRIPTNAME" -- "$@")
[ $? != 0 ] && usage

eval set -- "$TEMP"

CURRENCY="RUB"
METRIC="amount"
BEHAVIOUR="addition"
SHARD_SIZE="1"
FIELD=""

while true; do
  case "${1}" in
    --help                    ) usage ;;
    --time-range              ) TIME_RANGE="${2}" ; shift 2 ;;
    --context                 ) CONTEXT="${2}" ; shift 2 ;;
    --scope                   ) SCOPE+=("${2}") ; shift 2 ;;
    --scope-field             ) FIELD+=("${2}") ; shift 2 ;;
    --turnover-metric         ) METRIC="${2}" ; shift 2 ;;
    --currency                ) CURRENCY="${2}" ; shift 2 ;;
    --subtraction             ) BEHAVIOUR="subtraction" ; shift 1 ;;
    --shard-size              ) SHARD_SIZE="${2}" ; shift 2 ;;
    --                        ) shift 1 ; break ;;
    *                         ) usage ;;
  esac
done

ID="${1}"
STARTED_AT="${2}"
DESCRIPTION="${3}"

case "${TIME_RANGE}" in
  day   ) CALENDAR_RANGE="{\"day\":{}}" ;;
  week  ) CALENDAR_RANGE="{\"week\":{}}" ;;
  month ) CALENDAR_RANGE="{\"month\":{}}" ;;
  year  ) CALENDAR_RANGE="{\"year\":{}}" ;;
  *     ) usage ;;
esac

case "${CONTEXT}" in
  payproc    ) CONTEXT_TYPE="{\"payment_processing\":{}}" ;;
  withdrawal ) CONTEXT_TYPE="{\"withdrawal_processing\":{}}" ;;
  *          ) usage ;;
esac

SSEP=""
for s in ${FIELD[@]}; do
  FIELDS="${FIELDS}${SSEP}${s}"
  SSEP=","
done

SSEP=""
for s in ${SCOPE[@]}; do
  case "${s}" in
    party        ) SCOPES="${SCOPES}${SSEP}{\"party\":{}}" ;;
    shop         ) SCOPES="${SCOPES}${SSEP}{\"shop\":{}}" ;;
    wallet       ) SCOPES="${SCOPES}${SSEP}{\"wallet\":{}}" ;;
    identity     ) SCOPES="${SCOPES}${SSEP}{\"identity\":{}}" ;;
    paytool      ) SCOPES="${SCOPES}${SSEP}{\"payment_tool\":{}}" ;;
    provider     ) SCOPES="${SCOPES}${SSEP}{\"provider\":{}}" ;;
    terminal     ) SCOPES="${SCOPES}${SSEP}{\"terminal\":{}}" ;;
    email        ) SCOPES="${SCOPES}${SSEP}{\"payer_contact_email\":{}}" ;;
    sbp-phone    ) SCOPES="${SCOPES}${SSEP}{\"destination_field\":{\"field_path\":[\"phoneNumber\"]}}" ;;
    fields       ) SCOPES="${SCOPES}${SSEP}{\"destination_field\":{\"field_path\":[${FIELDS}]}}" ;;
    *            ) usage ;;
  esac
  SSEP=","
done

case "${METRIC}" in
  amount ) TURNOVER="{\"metric\": {\"amount\": {\"currency\": \"${CURRENCY}\"}}}" ;;
  number ) TURNOVER="{\"metric\": {\"number\": {}}}" ;;
  *      ) usage ;;
esac

[ -z "$ID" ] \
  || [ -z "$CONTEXT_TYPE" ] \
  || [ -z "$STARTED_AT" ] \
  || [ -z "$DESCRIPTION" ] \
  || [ -z "$TIME_RANGE" ] \
  && usage

JSON=$(cat <<END
  {
    "id": "${ID}",
    "started_at": "${STARTED_AT}",
    "description": "${DESCRIPTION}",
    "type": {"turnover": ${TURNOVER}},
    "time_range_type": {"calendar": ${CALENDAR_RANGE}},
    "shard_size": ${SHARD_SIZE},
    "scope": {"multi": [${SCOPES}]},
    "context_type": ${CONTEXT_TYPE},
    "op_behaviour": {"invoice_payment_refund": {"${BEHAVIOUR}": {}}}
  }
END
)

[ -f woorlrc ] && source woorlrc

"${WOORL[@]:-woorl}" \
    -s "${LIMITER_PROTO}/proto/configurator.thrift" \
    "http://${LIMITER:-limiter}:8022/v1/configurator" \
    Configurator Create "${JSON}"
