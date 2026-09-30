#!/bin/bash
# Claims the top NEW/TODO card from the board column linked to this repository and
# prints it as a prompt. Called by ~/.claude/commands/next.md with the session id.
# The project key is the repository folder name; set the same value as the group's
# agent key on the board.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kanban/config.json"
SESSIONS="${XDG_STATE_HOME:-$HOME/.local/state}/claude-kanban/sessions"

command -v jq >/dev/null || { echo "jq is required for the board integration."; exit 0; }
url="${KANBAN_URL:-$(jq -r '.url // empty' "$CONFIG" 2>/dev/null)}"
token="${KANBAN_TOKEN:-$(jq -r '.token // empty' "$CONFIG" 2>/dev/null)}"
if [ -z "$url" ] || [ -z "$token" ]; then
  echo "Board not configured: run the claude-kanban installer."; exit 0
fi

sid="$1"
case "$sid" in *[!A-Za-z0-9-]*) sid="" ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
key=$(basename "$root")

# The key goes in on stdin (-H @-), never on the command line.
resp=$(printf 'X-Agent-Token: %s\n' "$token" | curl -sS -m 10 --proto =https,http -X POST "$url/api/v1/tasks/agent/claim" \
  -H @- \
  --data-urlencode "key=$key" \
  --data-urlencode "sessionid=$sid" \
  --data-urlencode "host=$(hostname)") || { echo "Could not reach the board."; exit 0; }

# Mark this session as working a card, so the hooks report it. Sessions without
# a marker are never sent to the board. Markers older than 30 days are swept.
if [ -n "$sid" ] && [ "$(jq -r '.meta.claimed // false' <<<"$resp" 2>/dev/null)" = "true" ]; then
  (umask 077; mkdir -p "$SESSIONS" && : > "$SESSIONS/$sid")
  find "$SESSIONS" -type f -mtime +30 -delete 2>/dev/null
fi

jq -r --arg key "$key" '
  if .status != 1 then
    "Board error for project \"\($key)\": " + ((.mssg // []) | if type == "array" then join("; ") else tostring end)
  elif .meta.claimed != true then
    "Nothing to do: no new or to-do cards in \"\(.body.group.name)\"."
  else
    .body.prompt
    + (if .meta.tracked then "" else "\n\n(Session id missing: the board will not follow this card automatically.)" end)
  end' <<<"$resp" 2>/dev/null || echo "Unexpected answer from the board."
