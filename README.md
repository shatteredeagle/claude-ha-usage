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
2. Enable packages in `configuration.yaml` if you haven't: `packages: !include_dir_named packages`. If you already have a top-level `homeassistant:` block, add it inside that block; a second `homeassistant:` key would silently replace the first.
3. Create the `packages/` folder next to `configuration.yaml` if needed, copy `homeassistant/claude_usage.yaml` into it and restart HA.
4. Create a dashboard and paste `homeassistant/dashboard.json` into its raw configuration editor.

To report from more machines, clone the repo there and run `./install.sh --url <same url> --webhook-id <same id>` (or copy `~/.config/claude-ha/config` over first and run `./install.sh`). The config alone does nothing: the machine also needs the script and the `statusLine` setting, which the installer adds.

## How it behaves

- **No tokens used.** The statusline command is a local process outside the model; its output never enters the conversation.
- **Not live.** Numbers arrive only while a Claude Code session is running, and the limit percentages refresh when a session gets an API response. Posts are limited to one a minute; if updates arrive faster, the newest values are sent when the minute is up, so the last state of a burst is never lost. `sensor.claude_last_report` tells you how stale the data is.
- **Limits are account-wide, context is per session.** With several sessions open, the context sensor shows whichever reported last.
- **Runway is an average, not recent burn.** It is `(100 - used) / (used / hours since the window started)`, never below 0. A long idle stretch early in a window makes it optimistic. It can be longer than the time left in the window; the `hits_limit_before_reset` attribute on the runway sensors says whether you would actually hit 100% before the reset.
- The webhook is `local_only`, so HA only accepts it from your LAN. The webhook id is the only secret: it is kept in a mode-600 config file and passed to `curl` on stdin, not on the command line. Use `https://` if your HA is reachable that way.
- Small state files (last-sent time, latest payload) live in a private per-user folder under `$XDG_RUNTIME_DIR`, `$TMPDIR` or `~/.cache`.

## Uninstall

Remove `statusLine` from `~/.claude/settings.json` (or restore the first backup, `settings.json.bak-claude-ha`, if you had a statusline before; the installer never overwrites it), delete `~/.claude/statusline-ha.sh` and `~/.config/claude-ha/`, and remove the HA package and dashboard.

## License

MIT
