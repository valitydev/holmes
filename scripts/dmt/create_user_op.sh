#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o errtrace

export CHARSET=UTF-8
export LANG=C.UTF-8

EMAIL=${1}

NAME=${1}

USER_OP_PARAMS=$(cat <<END
{
  "email": "${EMAIL}",
  "name": "${NAME}"
}
END
)

woorl -s "damsel/proto/domain_config_v2.thrift" "http://dmt:8022/v1/domain/user_op" UserOpManagement Create "${USER_OP_PARAMS}" |
jq -r '.id'
