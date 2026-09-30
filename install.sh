#!/bin/bash
# claude-kanban installer: /next plus the Claude Code hooks that move the
# claimed card on a GrayTask / Scape notes board. Safe to run again (upgrades
# the scripts, changes the URL or key, never duplicates hooks).
set -euo pipefail
# Everything this writes (config with the key, settings backups) is for this
# user's eyes only.
umask 077

RAW_BASE="${KANBAN_SRC:-https://raw.githubusercontent.com/JcVollar/claude-kanban/main}"
FILES=(kanban-hook.sh kanban-next.sh next.md settings.snippet.json install.sh)

usage() {
  cat <<'EOF'
Install on this computer (no checkout needed; asks for the key):
  curl -fsSL https://raw.githubusercontent.com/JcVollar/claude-kanban/main/install.sh \
    | bash -s -- --url https://your-board

From a checkout:
  ./install.sh --url https://your-board --key sat_...
  ./install.sh --host user@server --url https://your-board   # install on another computer over ssh
  ./install.sh --uninstall [--host user@server]

Leave out --key and you are asked for it (hidden) - better than --key, which
puts the key in your shell history. Leave out --url/--key on a
re-run and the ones already configured are kept. Create one key per computer
in the app: a group's agent chip > Agent keys.
EOF
  exit "${1:-0}"
}
die() { echo "error: $*" >&2; exit 1; }

url=""; key=""; host=""; uninstall=0; key_stdin=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url="${2:-}"; shift 2 ;;
    --key) key="${2:-}"; shift 2 ;;
    --host) host="${2:-}"; shift 2 ;;
    --uninstall) uninstall=1; shift ;;
    --key-stdin) key_stdin=1; shift ;;   # internal: the key arrives on stdin (remote mode)
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done
url="${url%/}"
case "$host" in -*) die "--host must be user@server, not an option" ;; esac

# Ask on the terminal even when the script itself arrived on stdin (curl | bash).
ask_key() {
  if [ -r /dev/tty ]; then
    read -r -s -p "$1" key </dev/tty || true; echo >/dev/tty
  fi
}

# The files to install: next to this script when run from a checkout, else
# downloaded — piped from curl there is no checkout to read them from.
CLEANUP=""
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT
SRC=""
here="$(dirname "${BASH_SOURCE[0]:-}")"
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$here/kanban-hook.sh" ] && [ -f "$here/next.md" ]; then
  SRC="$(cd "$here" && pwd)"
fi
fetch_sources() {
  [ -n "$SRC" ] && return
  command -v curl >/dev/null || die "curl is required"
  SRC="$(mktemp -d)"; CLEANUP="$SRC"
  local f
  for f in "${FILES[@]}"; do
    curl -fsSL -m 20 "$RAW_BASE/$f" -o "$SRC/$f" || die "could not download $f from $RAW_BASE"
  done
}

# ---------------------------------------------------------------- remote mode
# Copy the files to the other computer and run the installer there. The key goes
# over the ssh connection's stdin, never on a command line, so it doesn't show
# up in the remote process list or shell history.
if [ -n "$host" ]; then
  fetch_sources
  if [ "$uninstall" -eq 0 ] && [ -z "$key" ]; then
    ask_key "Agent key for $host (Enter to keep the current one): "
  fi
  # A fresh, private directory on the other side: a guessable /tmp path would
  # let another user there swap install.sh before it runs as this user.
  tmp="$(ssh -- "$host" 'mktemp -d /tmp/claude-kanban-install.XXXXXXXX')" || die "could not reach $host"
  case "$tmp" in /tmp/claude-kanban-install.*) ;; *) die "unexpected temp dir from $host: $tmp" ;; esac
  scp -q -- "${FILES[@]/#/$SRC/}" "$host:$tmp/"
  args=()
  [ -n "$url" ] && args+=(--url "$url")
  [ "$uninstall" -eq 1 ] && args+=(--uninstall)
  printf '%s\n' "$key" | ssh -- "$host" "bash '$tmp/install.sh' --key-stdin ${args[*]@Q}; rc=\$?; rm -rf '$tmp'; exit \$rc"
  exit $?
fi

# ----------------------------------------------------------------- local mode
command -v jq >/dev/null || die "jq is required (apt install jq / brew install jq)"
command -v curl >/dev/null || die "curl is required"

BIN="$HOME/bin"
CMDS="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"
# The URL and key live in their own private file, NOT in settings.json's env:
# Claude Code exports that env into every command it runs, in every repo, so a
# build script or dependency could read the key without trying.
CONFDIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-kanban"
CONFIG="$CONFDIR/config.json"
STATEDIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-kanban"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON; fix it first"

# Drop every hook entry that runs kanban-hook.sh, leaving the user's own hooks.
STRIP='
  if .hooks then
    .hooks |= (with_entries(.value |= map(select(
      ([.hooks[]?.command // ""] | any(test("kanban-hook\\.sh"))) | not
    ))) | with_entries(select(.value | length > 0)))
  else . end'

write_settings() {  # $1 = jq program, rest = jq args
  local prog="$1"; shift
  cp "$SETTINGS" "$SETTINGS.bak"
  jq "$@" "$prog" "$SETTINGS.bak" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

if [ "$uninstall" -eq 1 ]; then
  rm -f "$BIN/kanban-hook.sh" "$BIN/kanban-next.sh" "$CMDS/next.md"
  rm -rf "$CONFDIR" "$STATEDIR"
  write_settings "$STRIP | if .env then .env |= del(.KANBAN_URL, .KANBAN_TOKEN) else . end"
  echo "Removed from $(hostname) (previous settings in $SETTINGS.bak)."
  exit 0
fi

if [ "$key_stdin" -eq 1 ]; then
  IFS= read -r key || true
elif [ -z "$key" ]; then
  ask_key "Agent key (Enter to keep the current one): "
fi

# Fall back to what is already configured, so a re-run can just upgrade. The
# settings.json env is where older versions kept them.
[ -n "$url" ] || url="$(jq -r '.url // empty' "$CONFIG" 2>/dev/null || true)"
[ -n "$key" ] || key="$(jq -r '.token // empty' "$CONFIG" 2>/dev/null || true)"
[ -n "$url" ] || url="$(jq -r '.env.KANBAN_URL // empty' "$SETTINGS")"
[ -n "$key" ] || key="$(jq -r '.env.KANBAN_TOKEN // empty' "$SETTINGS")"
url="${url%/}"
[ -n "$url" ] || die "no board URL: pass --url https://your-board"
[ -n "$key" ] || die "no agent key: pass --key, or create one in the app under Agent keys"
case "$key" in *[!A-Za-z0-9_-]*) die "that doesn't look like an agent key" ;; esac
# The key travels in a header on every request: plain http would hand it to
# anyone on the network. Only a board on this very computer may skip TLS.
case "$url" in
  https://*) ;;
  http://localhost|http://localhost:*|http://127.0.0.1|http://127.0.0.1:*|http://\[::1\]*) ;;
  http://*) die "use https:// - over plain http the key would travel unencrypted" ;;
  *) die "--url must start with https://" ;;
esac

# Check the key before touching anything. A hook event for a session the board
# has never seen is the one call that proves the key without moving a card.
resp="$(printf 'X-Agent-Token: %s\n' "$key" | curl -sS -m 10 --proto =https,http -X POST "$url/api/v1/tasks/agent/hook" \
  -H @- -F hook_event_name=Stop -F "session_id=install-check-$$" 2>&1)" \
  || die "could not reach $url: $resp"
status="$(jq -r '.status // empty' <<<"$resp" 2>/dev/null || true)"
if [ "$status" != "1" ]; then
  msg="$(jq -r '(.mssg // []) | if type=="array" then join("; ") else tostring end' <<<"$resp" 2>/dev/null || true)"
  die "the board at $url refused the key: ${msg:-unexpected answer: ${resp:0:200}}"
fi

fetch_sources
mkdir -p "$BIN" "$CMDS"
install -m 755 "$SRC/kanban-hook.sh" "$SRC/kanban-next.sh" "$BIN/"
install -m 644 "$SRC/next.md" "$CMDS/next.md"

mkdir -p "$CONFDIR"
jq -n --arg url "$url" --arg key "$key" '{url: $url, token: $key}' > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
chmod 600 "$CONFIG"

write_settings "$STRIP
  | if .env then .env |= del(.KANBAN_URL, .KANBAN_TOKEN) | (if .env == {} then del(.env) else . end) else . end
  | .hooks = (reduce (\$snip[0].hooks | to_entries[]) as \$e (.hooks // {};
      .[\$e.key] = ((.[\$e.key] // []) + \$e.value)))" \
  --arg url "$url" --arg key "$key" --slurpfile snip "$SRC/settings.snippet.json"
chmod 600 "$SETTINGS" "$SETTINGS.bak"

echo "Installed on $(hostname) for $url"
echo "  scripts:  $BIN/kanban-next.sh, $BIN/kanban-hook.sh"
echo "  command:  $CMDS/next.md"
echo "  key:      $CONFIG (readable by you only)"
echo "  settings: $SETTINGS (previous version in $SETTINGS.bak)"
echo "Start a new Claude Code session in a repo whose folder name matches a group's agent project, then run /next."
