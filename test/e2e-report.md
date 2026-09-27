# E2E report

Run: 2026-09-27 15:15:08 UTC

| Check | Result | Time | Details |
|---|---:|---:|---|
| make build (sqlite_fts5) | PASS | 2s | built ./hindsight |
| Index Claude/Codex/Pi real-format fixtures | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 3 changed, 0 skipped |
| No-op incremental scan; transcript bytes unchanged | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
| Incremental sync adds new file | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Changed source is replaced, not duplicated | PASS | 0s | claude: 11 messages codex: 5 messages pi: 5 messages 4 files, 1 changed, 0 skipped |
| Deleted source is removed from index | PASS | 0s | claude: 5 messages codex: 5 messages pi: 5 messages 3 files, 0 changed, 0 skipped |
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
| CLI --version | PASS | 0s | 0.1.0 |
| Empty query lists recent messages as JSONL | PASS | 0s | 3 rows |
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
| Hit-list truncation: ellipsis + whole Latin words | PASS | 0s | 3 hit rows end their clipped snippet in ellipsis; Latin token intact or omitted |
| Performance: 2k sessions / 200k messages (20 varied queries) | PASS | 0s | index=6211.85ms queries=20 median=21.98ms p95=28.91ms slowest=[{"query":"-perfneedle","ms":29.1,"timing":"timing startup=0.93ms\ntiming sync_walk=0.72ms\ntiming sync_stat=2.96ms\ntiming sync_sources=1.16ms\ntiming sync_changes=0.12ms\ntiming sync_counts=0.26ms\ntiming sync=5.24ms\ntiming query=13.87ms\ntiming snippet=0.12ms\ntiming render=0.28ms"},{"query":"\"neutral synthetic\"","ms":28.91,"timing":"timing startup=0.92ms\ntiming sync_walk=0.74ms\ntiming sync_stat=2.45ms\ntiming sync_sources=1.10ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.26ms\ntiming sync=4.67ms\ntiming query=14.42ms\ntiming snippet=0.13ms\ntiming render=0.29ms"},{"query":"\"synthetic message\"","ms":28.83,"timing":"timing startup=0.96ms\ntiming sync_walk=0.78ms\ntiming sync_stat=2.46ms\ntiming sync_sources=1.13ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.26ms\ntiming sync=4.75ms\ntiming query=13.93ms\ntiming snippet=0.13ms\ntiming render=0.27ms"}] |
| Search semantics: common term is ranked by message time, not insertion order | PASS | 0s | 300 rows; harnesses=['claude', 'codex']; newest=2026-10-01T10:00:01Z |
| Append sync: next CLI query finds new line; only tail parsed | PASS | 0s | sync_changes=0.32ms; claude: 2 messages codex: 200001 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Partial final line is withheld until newline | PASS | 0s | timing startup=0.95ms timing sync_walk=0.76ms timing sync_stat=2.62ms timing sync_sources=1.20ms timing sync_changes=0.11ms timing sync_counts=0.26ms timing sync=4.98ms timing query=1.37ms timing snippet=0.00ms timing render=0.00ms |
| Partial line is re-read and indexed when completed | PASS | 0s | claude: 2 messages codex: 200002 messages pi: 1 messages 2002 files, 0 changed, 0 skipped |
| Real stores: read-only independent lower-bound sanity | SKIP | 0s | Set HINDSIGHT_E2E_REAL=1 to opt in to reading this machine’s ~/.claude, ~/.codex, and ~/.pi stores. |

**Summary:** 47 PASS, 0 FAIL.
