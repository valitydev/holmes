# Wrap a woorl GetTrace array into a Mattermost trace-viewer envelope.
# Args: --arg backend --arg namespace --arg process_id

def maybe_decode:
  if (type == "object")
     and (.type | type == "string")
     and (.type | startswith("application/json"))
     and (.data | type == "string")
  then
    .data as $raw | .data = ($raw | try fromjson catch $raw)
  else
    .
  end;

if type != "array" then
  error("GetTrace did not return a JSON array of trace units")
else
  {
    schema_version: 1,
    meta: {
      backend: $backend,
      namespace: $namespace,
      process_id: $process_id,
      otel_trace_ids: (
        reduce (
          .[]
          | .header.otel_trace_id
          | select(. != null and (type == "string") and . != "")
        ) as $id ([]; if index($id) == null then . + [$id] else . end)
      )
    },
    trace: [
      .[]
      | .body |= walk(maybe_decode)
    ]
  }
end
