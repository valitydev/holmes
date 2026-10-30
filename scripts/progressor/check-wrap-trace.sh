#!/bin/bash

CWD="$(dirname $0)"

source "${CWD}/../lib/logging"

command -v jq >/dev/null 2>&1 || err "jq is required."

GOT=$(jq \
    --arg backend hg \
    --arg namespace invoice \
    --arg process_id inv-1 \
    -f "${CWD}/wrap-trace.jq" \
    "${CWD}/testdata/woorl-sample.json") \
    || err "jq transform failed on sample woorl payload."

echo "${GOT}" | jq -e '.schema_version == 1' >/dev/null \
    || err "expected schema_version 1"

echo "${GOT}" | jq -e '.trace[0].body.thrift_call.params.data.invoice_id == "inv-1"' >/dev/null \
    || err "expected decoded thrift_call params"

echo "${GOT}" | jq -e '.trace[1].body.content.data.withdrawal_id == "wd-1"' >/dev/null \
    || err "expected decoded content body"

echo "${GOT}" | jq -e '.trace[2].body.thrift_call.params.data == "not-json{"' >/dev/null \
    || err "expected invalid JSON data to stay a string"

echo "${GOT}" | jq -e '.meta.otel_trace_ids == ["bbb222","aaa111"]' >/dev/null \
    || err "expected unique otel_trace_ids in first-seen order"

if ! jq -ne --argjson a "${GOT}" --slurpfile b "${CWD}/testdata/sample.trace.json" \
    '$a == $b[0]' >/dev/null; then
    err "transformed sample does not match testdata/sample.trace.json"
fi

if jq --arg backend hg --arg namespace invoice --arg process_id inv-1 \
    -f "${CWD}/wrap-trace.jq" \
    >/dev/null 2>&1 <<'EOF'
{"exception":{"ProcessNotFound":{}}}
EOF
then
    err "exception payload should fail"
fi

IDS=$(jq -f "${CWD}/session-ids.jq" <<'EOF'
{
  "trace": [
    {"events": [{"payload": {"withdrawal": {"change": {"session": {"id": "s-2", "payload": {"started": {}}}}}}}, {"payload": {"adjustment": {"id": "adj-1"}}}]},
    {"events": [{"payload": {"session": {"id": "s-1", "payload": {"finished": {"result": {"succeeded": {}}}}}}}, {"payload": {"withdrawal": {"change": {"session": {"id": "s-2", "payload": {"finished": {}}}}}}}, {"payload": {"session": {"id": ""}}}]}
  ]
}
EOF
) || err "session id extraction failed."

echo "${IDS}" | jq -e '. == ["s-2","s-1"]' >/dev/null \
    || err "expected first-seen session ids s-2, s-1"

jq -f "${CWD}/session-ids.jq" "${CWD}/testdata/sample.trace.json" | jq -e '. == []' >/dev/null \
    || err "sample trace should have no session ids"

echo "ok"
