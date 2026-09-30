#!/bin/bash
# Claude Code hook -> notes board. Install as ~/bin/kanban-hook.sh and register it for
# Stop, Notification and UserPromptSubmit (see settings.snippet.json).
# The server decides what each event means; sessions never handed a card are ignored.
# Never blocks or fails Claude: missing config, no jq, or an offline board all exit 0.
[ -n "$KANBAN_URL" ] && [ -n "$KANBAN_TOKEN" ] && command -v jq >/dev/null || exit 0

input=$(cat)
args=()
for f in hook_event_name session_id last_assistant_message notification_type message prompt; do
  v=$(jq -r --arg f "$f" '.[$f] // empty' <<<"$input" 2>/dev/null)
  [ -n "$v" ] && args+=(--data-urlencode "$f=$v")
done

curl -s -m 5 -X POST "$KANBAN_URL/api/v1/tasks/agent/hook" \
  -H "X-Agent-Token: $KANBAN_TOKEN" "${args[@]}" >/dev/null 2>&1
exit 0
