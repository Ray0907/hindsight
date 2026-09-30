# E2E report

Run: 2026-09-30 02:01:39 UTC

| Check | Result | Time | Details |
|---|---:|---:|---|
| make build (sqlite_fts5) | PASS | 0s | built ./kioku |
| Index Claude/Codex/Pi real-format fixtures | PASS | 1s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 3 changed, 0 skipped |
| No-op incremental scan; transcript bytes unchanged | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
| Incremental sync adds new file | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Changed source is replaced, not duplicated | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Deleted source is removed from index | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
| Short-prefix omitted footer and --all-time | PASS | 0s | text/JSON hits and sessions, inclusive 7-day boundary, --all-time, filters, and cursors checked |
| Tool-order fixture indexed | PASS | 0s | claude: 9 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Conversation hits precede matching tool row in JSON order | PASS | 0s | roles=['asst', 'user', 'tool'] |
| Tool-only match remains searchable | PASS | 0s |  |
| Pagination/show fixture indexed | PASS | 0s | claude: 32 messages codex: 5 messages pi: 5 messages 5 files, 1 changed, 0 skipped |
| Cursor pages cover every hit exactly once | PASS | 5s | 23 unique refs across cursor pages; union equals --limit 500 |
| Default page size and cursor footer/JSON parity | PASS | 0s | 10 + 10 + 3 rows; text and JSON cursors appear only while more remain |
| Cursor rejects changed query and flags clearly | PASS | 0s |  |
| --sessions ranking/counts agree with hit list | PASS | 0s | 6 hits across 3 sessions; counts sum and best-hit rank agrees |
| show ref context and text hit marker | PASS | 0s | 5-message context, selected hit, resume command, project/cwd, and 400-cell truncation verified |
| show --all paginates the whole session | PASS | 3s | all 23 messages returned once across show --all pages |
| kioku --help exits with usage before search/index | PASS | 0s |  |
| query: snapshot (contains) | PASS | 0s |  |
| query: recoverytoken (contains) | PASS | 0s |  |
| query: resum (contains) | PASS | 0s |  |
| query: sume (empty) | PASS | 0s |  |
| query: "tea black" (empty) | PASS | 0s |  |
| query: naive (contains) | PASS | 0s |  |
| query: json_extract (contains) | PASS | 0s |  |
| query: low-water (contains) | PASS | 0s |  |
| query: S3 (contains) | PASS | 0s |  |
| query: cjk.c (contains) | PASS | 0s |  |
| query: 魚池 (contains) | PASS | 0s |  |
| query: 南投魚池 (empty) | PASS | 0s |  |
| query: 茶 (contains) | PASS | 0s |  |
| query: 日本語 (contains) | PASS | 0s |  |
| query: 한국어 (contains) | PASS | 0s |  |
| query: --flag (empty) | PASS | 0s |  |
| CLI --version | PASS | 0s | v0.1.2-10-g6a2b0f5-dirty |
| Empty query lists recent messages as compact JSON | PASS | 0s | 5 rows |
| Malformed quote query does not crash | PASS | 0s |  |
| Compact JSON search-page schema | PASS | 0s | 6 hits |
| JSON harness filter claude | PASS | 0s |  |
| JSON harness filter codex | PASS | 0s |  |
| JSON harness filter pi | PASS | 0s |  |
| TUI starts and displays matching hit | PASS | 0s |  |
| Unfocused zone dimming (SGR 2) | PASS | 0s |  |
| Hit color present in ANSI capture | PASS | 0s |  |
| Transcript folding ellipsis ⋯ | PASS | 0s |  |
| Full mode reveals non-hit transcript content | PASS | 0s |  |
| Highlight pen background color | PASS | 0s |  |
| Ctrl-C exits and restores terminal (process + alternate screen) | PASS | 0s |  |
| Resume Claude stub argv + cwd | PASS | 0s | claude\|<fixture>/home/work/demo\|--resume 11111111-1111-4111-8111-111111111111 |
| Resume codex stub argv + cwd | PASS | 0s | codex\|<fixture>/home/work/demo\|resume 22222222-2222-4222-8222-222222222222 |
| Resume pi stub argv + cwd | PASS | 0s | pi\|<fixture>/home/work/demo\|--session <fixture>/home/.pi/agent/sessions/-work-demo/33333333-3333-4333-8333-333333333333.jsonl |
| Editor stub launch + project directory | PASS | 0s | zed\|<repo>\|<fixture>/home/work/demo |
| Editor launch leaves TUI alive | PASS | 0s |  |
| TUI n/N visits matching tool hit | PASS | 0s | both directions retain the tool hit in transcript |
| Hit-list truncation: ellipsis + whole Latin words | PASS | 0s | 3 hit rows end their clipped snippet in ellipsis; Latin token intact or omitted |
| Performance: 2k sessions / 200k messages (20 varied queries) | PASS | 0s | index=5095.6ms queries=20 median=28.04ms p95=92.35ms slowest=[{"query":"-neutral","ms":93.68,"timing":"timing startup=1.03ms\ntiming sync_walk=0.97ms\ntiming sync_stat=3.23ms\ntiming sync_sources=1.46ms\ntiming sync_changes=0.14ms\ntiming sync_counts=0.28ms\ntiming sync=6.11ms"},{"query":"-perfneedle","ms":92.35,"timing":"timing startup=0.98ms\ntiming sync_walk=0.86ms\ntiming sync_stat=2.91ms\ntiming sync_sources=1.29ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.28ms\ntiming sync=5.47ms"},{"query":"\"neutral synthetic\"","ms":58.42,"timing":"timing startup=1.02ms\ntiming sync_walk=0.85ms\ntiming sync_stat=3.28ms\ntiming sync_sources=1.35ms\ntiming sync_changes=0.12ms\ntiming sync_counts=0.30ms\ntiming sync=5.93ms"}] |
| Search semantics: common term is ranked by message time, not insertion order | PASS | 0s | 10 rows; harnesses=['claude', 'codex']; newest=synthetic NEWEST_MATCH_MARKER |
| Append sync: next CLI query finds new line; only tail parsed | PASS | 1s | sync_changes=0.31ms; claude: 2 messages codex: 200001 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Partial final line is withheld until newline | PASS | 0s | timing startup=0.93ms timing sync_walk=0.88ms timing sync_stat=3.28ms timing sync_sources=1.37ms timing sync_changes=0.13ms timing sync_counts=0.27ms timing sync=5.96ms |
| Partial line is re-read and indexed when completed | PASS | 0s | claude: 2 messages codex: 200002 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Real stores: read-only independent lower-bound sanity | SKIP | 0s | Set KIOKU_E2E_REAL=1 to opt in to reading this machine’s ~/.claude, ~/.codex, and ~/.pi stores. |

**Summary:** 60 PASS, 0 FAIL.
