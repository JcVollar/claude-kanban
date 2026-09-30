#!/bin/bash
# Claude Code hook -> notes board. Registered for Stop, Notification and
# UserPromptSubmit by install.sh. The server decides what each event means.
# Never blocks or fails Claude: missing config, no jq, or an offline board all exit 0.
#
# Only sessions that claimed a card with /next are reported. Hooks fire for
# every Claude Code session on the computer, and their prompts and replies are
# nobody else's business - so a session with no marker from kanban-next.sh
# sends nothing at all.
command -v jq >/dev/null || exit 0

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
case "$sid" in ''|*[!A-Za-z0-9-]*) exit 0 ;; esac
[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/claude-kanban/sessions/$sid" ] || exit 0

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kanban/config.json"
url="${KANBAN_URL:-$(jq -r '.url // empty' "$CONFIG" 2>/dev/null)}"
token="${KANBAN_TOKEN:-$(jq -r '.token // empty' "$CONFIG" 2>/dev/null)}"
[ -n "$url" ] && [ -n "$token" ] || exit 0

args=()
for f in hook_event_name session_id last_assistant_message notification_type message prompt; do
  v=$(jq -r --arg f "$f" '.[$f] // empty' <<<"$input" 2>/dev/null)
  [ -n "$v" ] && args+=(--data-urlencode "$f=$v")
done

# The key goes in on stdin (-H @-), never on the command line, where any other
# user on the computer could read it from the process list.
printf 'X-Agent-Token: %s\n' "$token" \
  | curl -s -m 5 --proto =https,http -X POST "$url/api/v1/tasks/agent/hook" -H @- "${args[@]}" >/dev/null 2>&1
exit 0
