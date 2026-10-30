# First-seen session machine ids from a wrapped withdrawal envelope.
# Real GetTrace events nest the change: payload.withdrawal.change.session.id.
# Flat payload.session.id is the same SessionChange when the union is not wrapped.

reduce (
  .trace[]?.events[]?.payload
  | (.withdrawal.change.session.id // .session.id // empty)
  | select(type == "string" and . != "")
) as $id ([]; if index($id) == null then . + [$id] else . end)
