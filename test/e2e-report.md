# E2E report

Run: 2026-09-27 16:25:10 UTC

| Check | Result | Time | Details |
|---|---:|---:|---|
| make build (sqlite_fts5) | PASS | 0s | built ./hindsight |
| Index Claude/Codex/Pi real-format fixtures | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 3 changed, 0 skipped |
| No-op incremental scan; transcript bytes unchanged | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
| Incremental sync adds new file | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Changed source is replaced, not duplicated | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Deleted source is removed from index | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
| Tool-order fixture indexed | PASS | 0s | claude: 9 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Conversation hits precede matching tool row in JSON order | PASS | 0s | roles=['asst', 'user', 'tool'] |
| Tool-only match remains searchable | PASS | 0s |  |
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
| CLI --version | PASS | 0s | v0.1.1-2-g6e235c3-dirty |
| Empty query lists recent messages as JSONL | PASS | 0s | 4 rows |
| Malformed quote query does not crash | PASS | 0s |  |
| JSONL parse/schema: all required fields | PASS | 0s |        6 rows |
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
| Performance: 2k sessions / 200k messages (20 varied queries) | PASS | 0s | index=5394.54ms queries=20 median=23.55ms p95=30.78ms slowest=[{"query":"perfneed","ms":48.07,"timing":"timing startup=17.26ms\ntiming sync_walk=0.79ms\ntiming sync_stat=2.66ms\ntiming sync_sources=1.17ms\ntiming sync_changes=0.10ms\ntiming sync_counts=0.29ms\ntiming sync=5.01ms\ntiming query=5.49ms\ntiming snippet=0.48ms\ntiming render=0.31ms"},{"query":"perfneedle","ms":30.78,"timing":"timing startup=3.84ms\ntiming sync_walk=0.74ms\ntiming sync_stat=2.61ms\ntiming sync_sources=1.13ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.27ms\ntiming sync=4.86ms\ntiming query=5.26ms\ntiming snippet=0.46ms\ntiming render=0.27ms"},{"query":"\"synthetic message\"","ms":29.03,"timing":"timing startup=0.86ms\ntiming sync_walk=0.77ms\ntiming sync_stat=2.41ms\ntiming sync_sources=1.13ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.25ms\ntiming sync=4.70ms\ntiming query=14.71ms\ntiming snippet=0.14ms\ntiming render=0.26ms"}] |
| Search semantics: common term is ranked by message time, not insertion order | PASS | 0s | 300 rows; harnesses=['claude', 'codex']; newest=2026-10-01T10:00:01Z |
| Append sync: next CLI query finds new line; only tail parsed | PASS | 0s | sync_changes=0.29ms; claude: 2 messages codex: 200001 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Partial final line is withheld until newline | PASS | 0s | timing startup=0.96ms timing sync_walk=0.77ms timing sync_stat=2.62ms timing sync_sources=1.19ms timing sync_changes=0.12ms timing sync_counts=0.29ms timing sync=5.02ms timing query=1.55ms timing snippet=0.00ms timing render=0.00ms |
| Partial line is re-read and indexed when completed | PASS | 0s | claude: 2 messages codex: 200002 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Real stores: read-only independent lower-bound sanity | SKIP | 0s | Set HINDSIGHT_E2E_REAL=1 to opt in to reading this machine’s ~/.claude, ~/.codex, and ~/.pi stores. |

**Summary:** 51 PASS, 0 FAIL.
