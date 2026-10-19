#!/bin/bash

set -o errexit
set -o pipefail

CWD="$(dirname $0)"
SCRIPTNAME=$(basename $0)
FILE_STORAGE_PROTO="${CWD}/../../file-storage-proto"
MSGPACK_PROTO="${CWD}/../../msgpack-proto"

source "${CWD}/../lib/logging"

function usage {
  echo -e "Given file ID get a temporary download link for the file stored in file-storage."
  echo
  echo -e "Usage: $(em ${SCRIPTNAME} file_data_id [-d [output_dir]])"
  echo -e "  $(em file_data_id)          File ID (string)"
  echo -e "  -d, --download [dir]  Download the file instead of printing the link. The file is saved as"
  echo -e "                        dir/file_data_id/file_name (default dir: current directory),"
  echo -e "                        its absolute path is printed to stdout."
  echo -e "  -h, --help            Show this help message."
  echo
  echo -e "Environment:"
  echo -e "  $(em FILE_STORAGE)            file-storage host (default: file-storage-v2)"
  echo -e "  $(em FILE_STORAGE_URL_TTL)    Download link lifetime in seconds (default: 3600)"
  echo
  echo -e "More information:"
  echo -e "  https://github.com/valitydev/file-storage-proto/blob/master/proto/file_storage.thrift"
  exit $1
}

FILE_ID="${1}"
URL_TTL="${FILE_STORAGE_URL_TTL:-3600}"
DOWNLOAD=

case ${FILE_ID} in
  ""|"-h"|"--help" )
    usage 0
    ;;
  -* )
    usage 127
    ;;
  * )
    shift 1
    ;;
esac

case ${1} in
  "" )
    ;;
  "-d"|"--download" )
    DOWNLOAD=true
    OUTPUT_DIR="${2:-.}"
    ;;
  * )
    usage 127
    ;;
esac

[ -f woorlrc ] && source woorlrc

# Assemble protocol in a private temp dir, so that concurrent runs do not
# step on each other: file_storage.thrift includes "proto/msgpack.thrift".
PROTO_DIR="$(mktemp -d)"
trap "rm -rf ${PROTO_DIR}" EXIT

mkdir "${PROTO_DIR}/proto"
cp "${FILE_STORAGE_PROTO}"/proto/*.thrift "${PROTO_DIR}/"
cp "${MSGPACK_PROTO}/proto/msgpack.thrift" "${PROTO_DIR}/proto/msgpack.thrift"

function file_storage {
  "${WOORL[@]:-woorl}" \
    -s "${PROTO_DIR}/file_storage.thrift" \
    "http://${FILE_STORAGE:-file-storage-v2}:8022/file_storage/v2" \
    FileStorage "$@"
}

function timestamp_after {
  local epoch=$(( $(date +%s) + $1 ))
  date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "${epoch}" +%Y-%m-%dT%H:%M:%SZ
}

FILE_DATA=$(file_storage GetFileData "\"${FILE_ID}\"") \
  || err "Failed to get data of file $(em ${FILE_ID})" >&2

FILE_NAME=$(basename "$(echo "${FILE_DATA}" | jq -r '.file_name // empty')")
[ -z "${FILE_NAME}" -o "${FILE_NAME}" = "/" -o "${FILE_NAME}" = "." -o "${FILE_NAME}" = ".." ] \
  && FILE_NAME="${FILE_ID}"

EXPIRES_AT="$(timestamp_after ${URL_TTL})"
DOWNLOAD_URL=$(file_storage GenerateDownloadUrl "\"${FILE_ID}\"" "\"${EXPIRES_AT}\"" | jq -r .) \
  || err "Failed to generate download url for file $(em ${FILE_ID})" >&2

if [ -z "${DOWNLOAD}" ]; then
  echo "File:       ${FILE_NAME}"
  echo "Created at: $(echo "${FILE_DATA}" | jq -r '.created_at // empty')"
  echo "Expires at: ${EXPIRES_AT}"
  echo "URL:        ${DOWNLOAD_URL}"
  exit 0
fi

TARGET_DIR="${OUTPUT_DIR}/${FILE_ID}"
mkdir -p "${TARGET_DIR}"
TARGET="$(cd "${TARGET_DIR}" && pwd)/${FILE_NAME}"

info "Downloading file $(em ${FILE_ID}) ($(em ${FILE_NAME})) ..." >&2
curl -fsS --retry 3 -o "${TARGET}" "${DOWNLOAD_URL}" \
  || err "Failed to download file $(em ${FILE_ID})" >&2

echo "${TARGET}"
