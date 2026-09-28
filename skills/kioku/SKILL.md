---
name: kioku
description: Use when the user refers to earlier work from any coding-agent session (Claude Code, Codex, Pi) — "last time", "we discussed", "where did I", "that session where", 之前、上次、那時候 — or needs a past decision, error, command, or the session to resume.
---

# kioku: search past agent sessions

## Overview

`kioku` indexes every local Claude Code, Codex and Pi transcript and searches them at message level, including Chinese, Japanese and Korean. Use it instead of grepping `~/.claude`, `~/.codex` or `~/.pi`: it knows each store's format, ranks hits, and gives the resume command. It is read-only.

Output is paged (10 per page) so it never floods your context. Go wide to narrow, and only fetch the next page when you need it.

## Workflow

1. **Which sessions?** `kioku --sessions <query>`: one line per session with hits by role, e.g. `4 hits (you 2 · asst 1 · tool 1)`, and its best ref. Sessions with `you`/`asst` hits are where it was *discussed*. Tool-only sessions usually just quote it (reviews, pasted diffs, logs), so skip them unless nothing else fits.
2. **Which messages?** `kioku <query>`: one hit per line, each starting with a ref like `2c998a27ab4c:54`.
3. **What was said?** Run the `expand:` command it prints (`kioku show <ref> --query "<q>"`). You get the messages around the hit, the hit marked `>` and trimmed around the match, plus cwd and the `resume:` command.
   - `--full`: the whole hit message, no truncation.
   - `--context N`: more surrounding messages.
   - `kioku show <session-id> --all`: page through the whole session.
4. **More results?** Only if the answer isn't there yet, repeat the same command with `--cursor <token>` from the `cursor:` line. A cursor only works with the exact query and flags it came from.

Don't read the raw JSONL. `show --full` has everything.

## Queries

| Want | Write |
|---|---|
| all words, any order | `auth token` |
| exact phrase | `"black tea"` |
| exclude | `migration -rollback` |
| English prefix | `resum` matches resuming |
| CJK substring | `魚池` matches 南投縣魚池鄉 |

- The user may have worked in another language. Try both, e.g. `checkout` and `結帳`.
- Try synonyms before concluding nothing exists.
- Conversation hits rank above tool output.
- If you know the project, add `-p <project>` (its directory name). It removes most decoys in one step. `--harness claude|codex|pi` narrows by agent. `--json` gives structured output with `next_cursor`.

## Rules

- Run it non-interactively. With a terminal attached, plain `kioku` opens a TUI; if that happens, add `--json`.
- Report the finding, the session (project, date, agent) and its `resume:` command. Don't run the resume command yourself; that is the user's choice.
- Transcripts are private. Quote only what answers the question.
- `kioku --help` lists everything. If results look stale, run `kioku index`.

## Common mistakes

| Mistake | Fix |
|---|---|
| Grepping raw JSONL across three stores | `kioku --sessions` first |
| Answering from the first hit | Check `--sessions`, then `show` it to confirm |
| Opening a session by id to find the hit | Pass the ref (`id:idx`) from `--sessions` or the hit list |
| Asking for `--limit 300` "to be safe" | Page with `--cursor` only when needed |
| One English query, nothing found | Add the other language and synonyms |
