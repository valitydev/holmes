#!/bin/bash

PROTO_MODULE_RE='(damsel|[a-z]+-proto)'
GIT_OPTIONS='-c advice.detachedHead=false -c init.defaultBranch=master'

TARGET_DIR="$1"
[ -z "$TARGET_DIR" ] && {
    echo "usage: $0 <target-dir>"
    exit -1
}

function enumerate_proto_modules {
    git ls-files --error-unmatch --stage \
        | grep '^160000' \
        | awk '{ print $4 " " $2; }' \
        | grep -E "$PROTO_MODULE_RE"
}

function emit_clone_command {
    local name="$1"
    local sha1="$2"
    local branch="$(git config -f .gitmodules --get "submodule.${name}.branch")"
    local url="$(git config -f .gitmodules --get "submodule.${name}.url")"
    local target="${TARGET_DIR}/${name}"
    local git="git ${GIT_OPTIONS} -C ${target}"

    mkdir -p "${target}"
    $git init
    $git remote add origin "${url}"
    $git fetch origin "${sha1}"
    if [ -n "${branch}" ]; then
        $git fetch origin "${branch}"
        $git checkout -B "${branch}" "${sha1}"
        $git branch --set-upstream-to "origin/${branch}"
    else
        $git checkout "${sha1}"
    fi

}

enumerate_proto_modules | while read name sha1; do
    emit_clone_command $name $sha1
done
