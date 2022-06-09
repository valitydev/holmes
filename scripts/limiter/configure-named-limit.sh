#!/bin/bash

set -o errexit
set -o pipefail

CWD="$(dirname $0)"
SCRIPTNAME=$(basename $0)
LIMITER_PROTO="${CWD}/../../limiter-proto"

trap "rm -rf ${LIMITER_PROTO}/proto/proto" EXIT

source "${CWD}/../lib/logging"

USAGE=$(cat <<EOF

  $(em Create configuration usage in limit counting.)
  Usage: ${SCRIPTNAME} [--subtraction] <id> <name> <started-at> <description>
    $(em id)                        Limit config ID (string)
    $(em started-at)                Timestamp (RFC3339) Example: 2021-07-06T01:02:03Z
    $(em name)                      Limit name (string)
    $(em description)               Limit description (string)
    $(em --subtraction)             Limiter behaviour when process payment refund. After refund limit will decrease on refund amount.

  More information:
    https://github.com/valitydev/limiter-proto/blob/master/proto/configurator.thrift
EOF
)

function usage {
    echo -e "$USAGE"
    exit 127
}

TEMP=$(getopt -o "" --longoptions help,subtraction -n "$SCRIPTNAME" -- "$@")
[ $? != 0 ] && usage

eval set -- "$TEMP"

BEHAVIOUR="addition"

while true; do
  case "${1}" in
    --help                    ) usage ;;
    --subtraction             ) BEHAVIOUR="subtraction" ; shift 1 ;;
    --                        ) shift 1 ; break ;;
    *                         ) usage ;;
  esac
done

ID="${1}"
STARTED_AT="${2}"
NAME="${3}"
DESCRIPTION="${4}"

[ -z "$ID" -o -z "$STARTED_AT" -o -z "$NAME" -o -z "$DESCRIPTION" ] && usage

JSON=$(cat <<END
  {
    "id": "${ID}",
    "started_at": "${STARTED_AT}",
    "name": "${NAME}",
    "description": "${DESCRIPTION}",
    "op_behaviour": {"invoice_payment_refund": {"${BEHAVIOUR}": {}}}
  }
END
)

[ -f woorlrc ] && source woorlrc

"${WOORL[@]:-woorl}" \
    -s "${LIMITER_PROTO}/proto/configurator.thrift" \
    "http://${LIMITER:-limiter}:8022/v1/configurator" \
    Configurator CreateLegacy "${JSON}"
