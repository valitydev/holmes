#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o errtrace

export CHARSET=UTF-8
export LANG=C.UTF-8

EMAIL=${1}

NAME=${1}

AUTHOR_PARAMS=$(cat <<END
{
  "email": "${EMAIL}",
  "name": "${NAME}"
}
END
)

woorl -s "damsel/proto/domain_config_v2.thrift" "http://${DMT:-dmt}:8022/v1/domain/author" AuthorManagement Create "${AUTHOR_PARAMS}" |
jq -r 'if .exception == "AuthorAlreadyExists" then .data.id else .id end'
