# claude-kanban

Connects [Claude Code](https://claude.com/claude-code) terminals to a GrayTask / Scape notes board.
Link a board group to a repository once, and every card in that group becomes work any Claude Code
terminal in that repo can pull with `/next`. The card then moves across the board by itself as Claude works.

## How it works

1. **Link a group to a repo.** On the board, open a group's **Link agent** chip and enter the repository's
   folder name, for example `scape.v10` or `graytask10` (case doesn't matter). Each name can be linked to
   one group per site.
2. **Run `/next`** in a Claude Code session inside that repo. It takes the group's top **New / To do** card,
   sets it to **In progress**, and gives Claude the card as its task. Two terminals on the same repo always
   get different cards.
3. **The card follows the session.**

   | In the terminal | On the board |
   |---|---|
   | `/next` claims the card | **In progress** |
   | Claude asks for permission or input | **Waiting** |
   | Claude finishes its reply | **Review**, and the reply is saved as the task's **Result** |
   | You type a follow-up | back to **In progress** |

4. **Only you set Done.** Once a card is done, nothing from the terminal moves it again. Running `/next`
   again in the same session hands its unfinished card back for review first.

Only sessions that claimed a card with `/next` talk to the board. Your other Claude Code sessions send
nothing.

## Requirements

- Claude Code, logged in with a claude.ai account. With an API-key login the session id isn't available,
  so `/next` still claims the card but the board can't follow it.
- `bash`, `curl` and `jq` on the computer.
- A board that has the agent endpoints (Scape Tasks module), reachable over `https://`.
- An **agent key** for the computer (see below).

## Install

### 1. Create an agent key

In the app, open any group's agent chip, then **Agent keys**, and create a key named after the computer
(for example `my-laptop`). The key is shown **once**. Copy it.

Use one key per computer, so you can revoke a single one later without touching the others.

### 2. Run the installer on that computer

```bash
curl -fsSL https://raw.githubusercontent.com/JcVollar/claude-kanban/main/install.sh \
  | bash -s -- --url https://your-board.example.com
```

It asks for the key (the input is hidden), checks it against the board, and installs. The **Agent keys**
window shows this line with your board's URL already filled in.

### 3. Use it

Start a **new** Claude Code session (settings are read at startup) in a repo whose folder name matches a
linked group, and type `/next`.

## Other ways to run the installer

From a checkout of this repo:

```bash
git clone https://github.com/JcVollar/claude-kanban.git && cd claude-kanban

./install.sh --url https://your-board.example.com              # this computer
./install.sh --host user@server --url https://your-board.example.com   # another computer, over ssh
```

With `--host`, the installer copies itself to the other computer, runs there and cleans up. The key is
sent over the ssh connection, not on a command line.

| Task | Command |
|---|---|
| Upgrade the scripts | run the installer again. It keeps the configured URL and key |
| Switch board or key | run it again with a new `--url`, and paste the new key |
| Remove everything | `./install.sh --uninstall` (add `--host user@server` for another computer) |

`--key sat_...` also works, but it puts the key in your shell history. Leaving it out and pasting it
when asked is safer.

## What gets installed

| Path | What |
|---|---|
| `~/bin/kanban-next.sh` | Claims a card. `/next` runs it |
| `~/bin/kanban-hook.sh` | Reports session events for claimed cards |
| `~/.claude/commands/next.md` | The `/next` command |
| `~/.claude/settings.json` | Three hooks added (`Stop`, `Notification`, `UserPromptSubmit`). Your own hooks are kept, and the previous file is saved as `settings.json.bak` |
| `~/.config/claude-kanban/config.json` | Board URL and key, readable by you only |
| `~/.local/state/claude-kanban/sessions/` | Marks which sessions have claimed a card. Swept after 30 days |

## Security

- **The key only works on the board's claim and hook endpoints**, never the rest of the API. The server
  stores only a hash of it. Revoke a key under **Agent keys** and that computer is cut off.
- **The key is kept out of Claude Code's environment**, so the commands Claude runs don't inherit it. It is
  sent to `curl` on stdin, so it never shows in the process list, and it is only ever sent over `https`.
- **Only `/next` sessions are reported.** Prompts and replies from any other session never leave the
  computer.
- **Board access steers Claude.** A card's text becomes Claude's instructions in that repo. Treat edit access
  to linked groups like access to the repo itself. Claude's own permission prompts still apply.
- **A key is not tied to one group.** Any key can claim cards from any linked group on its board. Keep one
  key per computer, and revoke keys for computers you no longer use.
- **Installing runs this repo's code.** `curl … | bash` runs whatever is on `main` at that moment. Read
  `install.sh` first if you like; it is short.

## Troubleshooting

| Message | Meaning |
|---|---|
| `Board not configured` | No URL or key yet. Run the installer |
| `No task group is linked to project 'x'` | No group's agent key matches this repo's folder name `x` |
| `A valid agent key is required` | The key is wrong or revoked. Create a new one and run the installer again |
| `Nothing to do` | The linked group has no New / To do cards |
| `Session id missing` | Claude Code is logged in with an API key. The card is claimed, but the board can't follow the session |
| The card never moves after `/next` | Start a new session after installing, because hooks are read at startup |
