#!/bin/bash

set -o errexit
set -o pipefail
set -o errtrace

CWD="$(dirname $0)"
DAMSEL="${CWD}/../damsel"

USAGE=$(cat <<EOF
Usage: ${SCRIPTNAME} plan-id
  Shows a plan given a plan-id
  plan-id     Posting plan ID (string)

More information:
  [1]: https://github.com/valitydev/damsel
  [2]: https://github.com/valitydev/damsel/blob/d384c125/proto/accounter.thrift#L70
EOF
)

function usage {
    echo "${USAGE}"
    exit 127
}

[ -f woorlrc ] && source woorlrc

PLANID="${1}"
[ -z "${PLANID}" ] && usage

ACCOUNTER="http://${SHUMWAY:-shumway}:${SHUMWAY_PORT:-8022}/accounter"

"${WOORL[@]:-woorl}" -s "${DAMSEL}/proto/accounter.thrift" \
    "${ACCOUNTER}" Accounter GetPlan "\"${PLANID}\""
