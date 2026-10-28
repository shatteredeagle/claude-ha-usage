#!/usr/bin/env bash
# Installs the Claude Code -> Home Assistant usage forwarder. Safe to re-run.
#   ./install.sh [--url http://homeassistant.local:8123] [--webhook-id ID] [--force]
# --force replaces an existing, different statusLine in ~/.claude/settings.json.
set -euo pipefail

url=; hook=; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) url=${2:?--url needs a value}; shift 2 ;;
    --webhook-id) hook=${2:?--webhook-id needs a value}; shift 2 ;;
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
ours="~/.claude/statusline-ha.sh"

# Reuse an existing config so re-running (or adding a second machine) keeps the same webhook.
HA_URL=; WEBHOOK_ID=
[ -r "$cfg" ] && . "$cfg"
[ -n "$url" ] || url=$HA_URL
[ -n "$hook" ] || hook=$WEBHOOK_ID
if [ -z "$url" ]; then
  if [ -t 0 ]; then
    read -r -p "Home Assistant URL [http://homeassistant.local:8123]: " url || true
    url=${url:-http://homeassistant.local:8123}
  else
    echo "No Home Assistant URL: pass --url http://<host>:8123" >&2; exit 2
  fi
fi
url=${url%/}
case "$url" in
  http://*|https://*) ;;
  *) echo "URL must start with http:// or https://" >&2; exit 2 ;;
esac
case "$url$hook" in
  *[\"\\[:space:]]*) echo "URL and webhook id must not contain quotes, backslashes or spaces" >&2; exit 2 ;;
esac
if [ -n "$hook" ] && ! [[ $hook =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "Webhook id may only contain letters, digits, - and _ (and must not start with -)" >&2; exit 2
fi
[ -n "$hook" ] || hook="claude-usage-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

[ -f "$settings" ] || { mkdir -p "$HOME/.claude"; echo '{}' > "$settings"; }
jq -e 'type == "object"' "$settings" >/dev/null 2>&1 || { echo "$settings is not a valid JSON object; fix it and re-run." >&2; exit 1; }

mkdir -p "$cfgdir" "$HOME/.claude"
( umask 077; printf 'HA_URL=%q\nWEBHOOK_ID=%q\n' "$url" "$hook" > "$cfg" )
chmod 600 "$cfg"
install -m 755 "$here/statusline-ha.sh" "$target"

current=$(jq -r '.statusLine.command // empty' "$settings")
if [ "$current" = "$ours" ]; then
  echo "statusLine already set in $settings"
elif [ -n "$current" ] && [ "$force" -eq 0 ]; then
  echo "NOT changed: $settings already has a statusLine ($current)."
  echo "Re-run with --force to replace it, or call $target from your own script."
else
  # Keep the first backup; later runs get a timestamped one so the original is never overwritten.
  bak="$settings.bak-claude-ha"
  [ -e "$bak" ] && bak="$bak.$(date +%s)"
  cp "$settings" "$bak"
  jq --arg c "$ours" '.statusLine = {type: "command", command: $c}' "$bak" > "$settings.tmp" && cat "$settings.tmp" > "$settings" && rm -f "$settings.tmp"
  echo "statusLine set in $settings (backup: $bak)"
fi

cat <<EOF

Claude Code side done. Now Home Assistant:

 1. Add this line to secrets.yaml:
      claude_usage_webhook: $hook

 2. Enable packages in configuration.yaml. If you already have a top-level
    "homeassistant:" block, add the "packages:" line inside it (a second
    "homeassistant:" key would silently replace the first). Otherwise add:
      homeassistant:
        packages: !include_dir_named packages

 3. Create the packages/ folder next to configuration.yaml if it is missing, copy
    homeassistant/claude_usage.yaml into it, then restart Home Assistant.

 4. Settings > Dashboards > Add dashboard (from scratch), open it, three dots >
    Edit > three dots > Raw configuration editor, paste homeassistant/dashboard.json.

Restart Claude Code, send a message, and the sensors fill in within a minute.
To report from another machine: copy this repo there and run ./install.sh
after copying ~/.config/claude-ha/config over (it reuses that config).
EOF
