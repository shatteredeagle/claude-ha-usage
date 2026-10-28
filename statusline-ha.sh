#!/usr/bin/env bash
# Claude Code statusline: prints "ctx · 5h · 7d" usage and forwards it to Home Assistant (at most 1 post/min,
# with a trailing post so the last values of a burst are never dropped).
# Config: ${XDG_CONFIG_HOME:-~/.config}/claude-ha/config  (HA_URL=..., WEBHOOK_ID=...), written by install.sh.
in=$(cat)

jq -r 'def p: if . == null then "?" else "\(floor)%" end;
  "ctx \(.context_window.used_percentage | p) · 5h \(.rate_limits.five_hour.used_percentage | p) · 7d \(.rate_limits.seven_day.used_percentage | p)"' \
  <<<"$in" 2>/dev/null || echo "ctx ? · 5h ? · 7d ?"

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/claude-ha/config"
[ -r "$cfg" ] || exit 0
HA_URL=; WEBHOOK_ID=
# shellcheck disable=SC1090
. "$cfg"
[ -n "$HA_URL" ] && [ -n "$WEBHOOK_ID" ] || exit 0
case "$HA_URL$WEBHOOK_ID" in *[\"\\[:space:]]*) exit 0 ;; esac

data=$(jq -c --arg host "$(hostname -s 2>/dev/null || uname -n)" '{host:$host, model:(.model.display_name // null), session:(.session_id // null),
  ctx:(.context_window.used_percentage // null),
  five_pct:(.rate_limits.five_hour.used_percentage // null), five_resets:(.rate_limits.five_hour.resets_at // null),
  seven_pct:(.rate_limits.seven_day.used_percentage // null), seven_resets:(.rate_limits.seven_day.resets_at // null)}' \
  <<<"$in" 2>/dev/null) || exit 0
[ -n "$data" ] || exit 0

# Private per-user state dir; refuse anything we don't own so a planted dir/file elsewhere can't be used.
base=${XDG_RUNTIME_DIR:-}
[ -d "$base" ] && [ -w "$base" ] || { base=${TMPDIR:-$HOME/.cache}; mkdir -p "$base" 2>/dev/null; }
dir="$base/claude-ha-$(id -u)"
mkdir -p -m 700 "$dir" 2>/dev/null
[ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] || exit 0

payload="$dir/payload.json"; stamp="$dir/last"; lock="$dir/trailing.lock"
printf '%s' "$data" > "$payload.$$" && mv "$payload.$$" "$payload"

now=$(date +%s); last=$(cat "$stamp" 2>/dev/null)
case $last in ''|*[!0-9]*) last=0 ;; esac
(( last > now )) && last=0

# The URL carries the webhook secret, so it goes to curl on stdin (-K -), not on the command line.
send() {
  date +%s > "$stamp"
  printf 'url = "%s/api/webhook/%s"\n' "${HA_URL%/}" "$WEBHOOK_ID" |
    curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @"$payload" -K - >/dev/null 2>&1
}

if (( now - last >= 60 )); then
  send </dev/null >/dev/null 2>&1 &
else
  # Throttled: schedule one trailing send of the latest payload. A killed sender leaves a stale lock; clear it.
  [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
  if mkdir "$lock" 2>/dev/null; then
    ( sleep $((60 - (now - last))); send; rmdir "$lock" ) </dev/null >/dev/null 2>&1 &
  fi
fi
