#!/bin/bash
# Claims the top NEW/TODO card from the board column linked to this repository and
# prints it as a prompt. Called by ~/.claude/commands/next.md with the session id.
# The project key is the repository folder name; set the same value as the group's
# agent key on the board.
if [ -z "$KANBAN_URL" ] || [ -z "$KANBAN_TOKEN" ]; then
  echo "Board not configured: set KANBAN_URL and KANBAN_TOKEN."; exit 0
fi

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
key=$(basename "$root")

resp=$(curl -sS -m 10 -X POST "$KANBAN_URL/api/v1/tasks/agent/claim" \
  -H "X-Agent-Token: $KANBAN_TOKEN" \
  --data-urlencode "key=$key" \
  --data-urlencode "sessionid=$1" \
  --data-urlencode "host=$(hostname)") || { echo "Could not reach the board."; exit 0; }

jq -r --arg key "$key" '
  if .status != 1 then
    "Board error for project \"\($key)\": " + ((.mssg // []) | if type == "array" then join("; ") else tostring end)
  elif .meta.claimed != true then
    "Nothing to do: no new or to-do cards in \"\(.body.group.name)\"."
  else
    .body.prompt
    + (if .meta.tracked then "" else "\n\n(Session id missing: the board will not follow this card automatically.)" end)
  end' <<<"$resp" 2>/dev/null || echo "Unexpected answer from the board: $resp"
