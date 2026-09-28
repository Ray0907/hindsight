# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

(The shipping product is a terminal TUI. The web surface under `mock/` is a faithful HTML mock of that TUI, used to decide the visual world before the Go build.)

## Stack

Go single binary. Bubble Tea + Lipgloss for the TUI. mattn/go-sqlite3 (build tag `sqlite_fts5`) with fts5-cjk (`cjk.c`) statically linked via `sqlite3_auto_extension`; verified 2026-09-27.

## Users

Developers who run several coding agents (Claude Code, Codex, Pi) side by side and write in Chinese, Japanese, Korean and English. Job: find the past session where something was discussed or solved, read the exact message, and resume that session in its own tool.

## Product Purpose

Full-text search over every local coding-agent transcript, at message granularity, from any terminal. Success: type a few words in any of CJK or English, land on the message that matters within seconds, press Enter to resume it in its original directory.

## Positioning

Not tied to any one agent (pi-session-hub lives only inside Pi). Indexes the whole transcript, not title plus excerpt. CJK search actually works, through the author's own fts5-cjk tokenizer. Hits are messages ranked by BM25, not sessions sorted by date.

## Operating Context

Runs in the user's own terminal emulator, with the user's own monospace font and theme; the product controls color, box-drawing glyphs, layout and motion only. Read-only against every harness store; the only file it writes is its own index. Also callable non-interactively (`--json`) by agents.

## Capabilities and Constraints

- Sources v1: Claude Code (`~/.claude/projects`), Codex (`~/.codex/sessions`), Pi (`~/.pi/agent/sessions`).
- Query syntax follows fts5-cjk: bare word = contiguous phrase, space = AND, "quotes" = phrase, `-word` = exclude.
- Resume commands: `claude --resume <id>`, `codex resume <id>`, Pi session path.
- Open: product name `kioku` is provisional.

## Brand Commitments

None yet besides the name candidate. Related OSS by the same author: fts5-cjk (github.com/Ray0907/fts5-cjk).

## Evidence on Hand

No users, benchmarks or testimonials yet; none may be invented. Demo data in mocks is synthetic and labelled so.

## Product Principles

1. The transcript is the content; styling never competes with reading it.
2. Every keystroke answers instantly; motion never delays input.
3. CJK is first-class: full-width characters align, highlights land on the right characters.
4. Recognisably its own tool, not another fzf or lazygit skin.
5. Looks right on both light and dark terminal themes.

## Accessibility & Inclusion

Must be legible on light and dark terminal backgrounds; state must not rely on color alone (hits also carry a glyph marker). Chinese, Japanese, Korean and English text all first-class.
