---
title: The heddle command
description: Install, start, stop, update, back up and configure Heddle from the terminal.
sidebar:
  order: 3
---

The `heddle` command comes with every install. It installs Heddle and [Treadle](https://github.com/heddlehq/Treadle), runs them, and looks after them. Everything it says is in English or Portuguese, following your system.

## Running

| Command | Does |
| --- | --- |
| `heddle` or `heddle start` | Starts Heddle in this terminal. `Ctrl+C` stops it. |
| `heddle start -d` | Starts it in the background. |
| `heddle stop` | Stops Heddle and its database, wherever it was started. |
| `heddle restart` | Stops and starts again, in the background. |
| `heddle status` | What's running and how it's set up. `--json` for scripts. |
| `heddle logs -f` | Follows the logs. `--db` shows the database's. |
| `heddle open` | Opens Heddle in the browser. |
| `heddle version` | The versions installed. |

## Settings

| Command | Does |
| --- | --- |
| `heddle config list` | Lists the settings, with secrets hidden. |
| `heddle config get KEY` | Prints one. |
| `heddle config set KEY=VALUE...` | Changes them. Restart for them to apply. |
| `heddle config unset KEY...` | Removes them. |
| `heddle config path` | Where the settings file is. |
| `heddle setup` | Changes the AI, step by step. |
| `heddle autostart on` / `off` | Starts Heddle with the computer. Needs systemd. |

The keys are the [environment variables](/docs/reference/configuration/).

## Looking after it

| Command | Does |
| --- | --- |
| `heddle doctor` | Checks that everything is in order, your AI key included. |
| `heddle update` | Updates Heddle, Treadle and itself. `--check` only looks. |
| `heddle backup` | Copies your data. Heddle stops for the copy and starts again. |
| `heddle backup list` | Lists the copies. |
| `heddle backup restore NAME` | Puts a copy back, moving your current data aside. |
| `heddle uninstall` | Removes Heddle. `--keep-data` keeps your data. |

`heddle update` makes a backup first, and keeps the last three.

## Installing

| Command | Does |
| --- | --- |
| `heddle install` | Installs Heddle, asking what you want. |
| `heddle install --yes` | Installs with the defaults, asking nothing. |
| `heddle install --help` | Every option, one per question. |

See [Installation](/docs/start/installation/).
