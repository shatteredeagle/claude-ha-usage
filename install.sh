#!/usr/bin/env bash
# Installs the Claude Code -> Home Assistant usage forwarder.
#   ./install.sh [--url http://homeassistant.local:8123] [--webhook-id ID] [--force]
# --force replaces an existing, different statusLine in ~/.claude/settings.json.
set -euo pipefail

url=; hook=; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url=$2; shift 2 ;;
    --webhook-id) hook=$2; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

for bin in jq curl; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

here=$(cd "$(dirname "$0")" && pwd)
cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-ha"
cfg="$cfgdir/config"
settings="$HOME/.claude/settings.json"
target="$HOME/.claude/statusline-ha.sh"

# Reuse an existing config so re-running (or adding a second machine) keeps the same webhook.
HA_URL=; WEBHOOK_ID=
[ -r "$cfg" ] && . "$cfg"
[ -n "$url" ] || url=$HA_URL
[ -n "$hook" ] || hook=$WEBHOOK_ID
if [ -z "$url" ]; then
  read -r -p "Home Assistant URL [http://homeassistant.local:8123]: " url
  url=${url:-http://homeassistant.local:8123}
fi
url=${url%/}
[ -n "$hook" ] || hook="claude-usage-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

mkdir -p "$cfgdir" "$HOME/.claude"
( umask 077; printf 'HA_URL=%q\nWEBHOOK_ID=%q\n' "$url" "$hook" > "$cfg" )
install -m 755 "$here/statusline-ha.sh" "$target"

[ -f "$settings" ] || echo '{}' > "$settings"
current=$(jq -r '.statusLine.command // empty' "$settings")
if [ -n "$current" ] && [ "$current" != "~/.claude/statusline-ha.sh" ] && [ "$force" -eq 0 ]; then
  echo "NOT changed: $settings already has a statusLine ($current)."
  echo "Re-run with --force to replace it, or call $target from your own script."
else
  cp "$settings" "$settings.bak-claude-ha"
  jq '.statusLine = {type: "command", command: "~/.claude/statusline-ha.sh"}' "$settings.bak-claude-ha" > "$settings"
  echo "statusLine set in $settings (backup: $settings.bak-claude-ha)"
fi

cat <<EOF

Claude Code side done. Now Home Assistant:

 1. Add this line to secrets.yaml:
      claude_usage_webhook: $hook

 2. Add this to configuration.yaml (once, if you don't use packages yet):
      homeassistant:
        packages: !include_dir_named packages

 3. Copy homeassistant/claude_usage.yaml to <config>/packages/claude_usage.yaml,
    then restart Home Assistant.

 4. Settings > Dashboards > Add dashboard (from scratch), open it, three dots >
    Edit > three dots > Raw configuration editor, paste homeassistant/dashboard.json.

Restart Claude Code, send a message, and the sensors fill in within a minute.
EOF
