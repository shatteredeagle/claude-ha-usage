# claude-ha-usage

Track your Claude Code (Claude.ai subscription) usage in Home Assistant: the 5-hour and 7-day limit windows, the current session's context fill, and a rough runway based on your pace.

Claude Code passes a JSON blob to its `statusLine` command on every update. That blob includes `rate_limits.five_hour`, `rate_limits.seven_day` and `context_window.used_percentage`. This repo's script prints a short status line and forwards the numbers to a Home Assistant webhook. HA turns them into sensors, keeps the history and draws the dashboard.

## What you get

| Entity | Meaning |
|---|---|
| `sensor.claude_5h_used` / `sensor.claude_7d_used` | Account-wide % of each limit window used (0 once the window has reset) |
| `sensor.claude_5h_resets` / `sensor.claude_7d_resets` | When each window resets |
| `sensor.claude_context_used` | Context fill of the most recently reporting session (attributes: host, model, session) |
| `sensor.claude_5h_runway` / `sensor.claude_7d_runway` | Hours until 100% if the window's average pace continues |
| `sensor.claude_5h_projected` / `sensor.claude_7d_projected` | Projected % at reset at that pace |
| `sensor.claude_last_report` | When Claude Code last reported |

## Requirements

- Claude Code with a Claude.ai subscription (Pro/Max). `rate_limits` is only present for subscribers, and only after the first API response of a session.
- `jq` and `curl` on each machine that runs Claude Code. Linux, macOS and WSL are fine.
- Home Assistant 2024.10 or newer (the `triggers:` / `trigger: webhook` template syntax), reachable from that machine.

## Install

On the machine that runs Claude Code:

```sh
git clone https://github.com/shatteredeagle/claude-ha-usage
cd claude-ha-usage
./install.sh --url http://homeassistant.local:8123
```

The installer writes `~/.config/claude-ha/config` (URL and a generated webhook id, mode 600), copies the script to `~/.claude/statusline-ha.sh` and sets `statusLine` in `~/.claude/settings.json`. If you already have a different `statusLine` it stops and tells you; use `--force` to replace it, or call `statusline-ha.sh` from your own script (it reads the same JSON on stdin and prints one line).

It then prints the Home Assistant steps:

1. Add `claude_usage_webhook: <id>` to `secrets.yaml`.
2. Enable packages in `configuration.yaml` if you haven't (`homeassistant: packages: !include_dir_named packages`).
3. Copy `homeassistant/claude_usage.yaml` to `packages/claude_usage.yaml` and restart HA.
4. Create a dashboard and paste `homeassistant/dashboard.json` into its raw configuration editor.

To report from more machines, copy `~/.config/claude-ha/config` to them (or run `install.sh --url ... --webhook-id <same id>`).

## How it behaves

- **No tokens used.** The statusline command is a local process outside the model; its output never enters the conversation.
- **Not live.** Numbers arrive only while a Claude Code session is running, at most once a minute, and the limit percentages refresh when a session gets an API response. `sensor.claude_last_report` tells you how stale they are.
- **Limits are account-wide, context is per session.** With several sessions open, the context sensor shows whichever reported last.
- **Runway is an average, not recent burn.** It is `(100 - used) / (used / hours since the window started)`. A long idle stretch early in a window makes it optimistic.
- The webhook is `local_only`, so HA only accepts it from your LAN.

## Uninstall

Remove `statusLine` from `~/.claude/settings.json` (a backup of the previous file is at `settings.json.bak-claude-ha`), delete `~/.claude/statusline-ha.sh` and `~/.config/claude-ha/`, and remove the HA package and dashboard.

## License

MIT
