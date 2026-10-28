#!/usr/bin/env bash
# Claude Code statusline: prints "ctx · 5h · 7d" usage and forwards it to Home Assistant (throttled to 1/min).
# Config: ${XDG_CONFIG_HOME:-~/.config}/claude-ha/config  (HA_URL=..., WEBHOOK_ID=...), written by install.sh.
in=$(cat)

jq -r 'def p: if . == null then "?" else "\(floor)%" end;
  "ctx \(.context_window.used_percentage | p) · 5h \(.rate_limits.five_hour.used_percentage | p) · 7d \(.rate_limits.seven_day.used_percentage | p)"' <<<"$in"

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/claude-ha/config"
[ -r "$cfg" ] || exit 0
HA_URL=; WEBHOOK_ID=
# shellcheck disable=SC1090
. "$cfg"
[ -n "$HA_URL" ] && [ -n "$WEBHOOK_ID" ] || exit 0

stamp="${XDG_RUNTIME_DIR:-/tmp}/claude-ha-last-$(id -u)"
[ -w "$(dirname "$stamp")" ] || stamp="/tmp/claude-ha-last-$(id -u)"
now=$(date +%s); last=$(cat "$stamp" 2>/dev/null || echo 0)
(( now - last >= 60 )) || exit 0
echo "$now" > "$stamp"

data=$(jq -c --arg host "$(hostname -s)" '{host:$host, model:(.model.display_name // null), session:(.session_id // null),
  ctx:(.context_window.used_percentage // null),
  five_pct:(.rate_limits.five_hour.used_percentage // null), five_resets:(.rate_limits.five_hour.resets_at // null),
  seven_pct:(.rate_limits.seven_day.used_percentage // null), seven_resets:(.rate_limits.seven_day.resets_at // null)}' <<<"$in")
curl -s -m 5 -X POST -H 'Content-Type: application/json' -d "$data" \
  "${HA_URL%/}/api/webhook/$WEBHOOK_ID" >/dev/null 2>&1 &
