# E2E report

Run: 2026-09-27 09:49:46 UTC

| Check | Result | Time | Details |
|---|---:|---:|---|
| make build (sqlite_fts5) | PASS | 0s | built ./hindsight |
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
| query: 茶 (contains) | PASS | 1s |  |
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
| Performance: 2k sessions / 200k messages (20 varied queries) | PASS | 0s | index=4188.6ms queries=20 median=15.92ms p95=92.19ms slowest=[{"query":"-perfneedle","ms":94.95,"timing":"timing startup=5.85ms\ntiming sync_walk=0.69ms\ntiming sync_stat=2.50ms\ntiming sync_sources=1.11ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.28ms\ntiming sync=4.70ms\ntiming query=77.40ms\ntiming snippet=0.02ms\ntiming render=0.30ms"},{"query":"-neutral","ms":92.19,"timing":"timing startup=0.85ms\ntiming sync_walk=0.81ms\ntiming sync_stat=2.44ms\ntiming sync_sources=1.14ms\ntiming sync_changes=0.11ms\ntiming sync_counts=0.27ms\ntiming sync=4.78ms\ntiming query=78.25ms\ntiming snippet=0.03ms\ntiming render=0.33ms"},{"query":"\"large fixture\"","ms":29.72,"timing":"timing startup=1.71ms\ntiming sync_walk=0.76ms\ntiming sync_stat=2.62ms\ntiming sync_sources=1.14ms\ntiming sync_changes=0.10ms\ntiming sync_counts=0.25ms\ntiming sync=4.90ms\ntiming query=0.18ms\ntiming hydrate=0.78ms\ntiming snippet=0.09ms\ntiming render=0.27ms"}] |
| Append sync: next CLI query finds new line; only tail parsed | PASS | 0s | sync_changes=0.28ms; claude: 0 messages codex: 200001 messages pi: 0 messages 2000 files, 0 changed, 0 skipped |
| Partial final line is withheld until newline | PASS | 0s | timing startup=0.94ms timing sync_walk=0.77ms timing sync_stat=2.46ms timing sync_sources=1.10ms timing sync_changes=0.11ms timing sync_counts=0.28ms timing sync=4.75ms timing query=0.12ms timing snippet=0.00ms timing render=0.00ms |
| Partial line is re-read and indexed when completed | PASS | 0s | claude: 0 messages codex: 200002 messages pi: 0 messages 2000 files, 0 changed, 0 skipped |
| Real stores: read-only independent lower-bound sanity | PASS | 34s | independent: harness total_jsonl raw_user_assistant_text_blocks;claude 161 2481;codex 334 11091;pi 1065 22076;indexed: harness sessions message_rows;claude 121 9574;codex 334 70497;pi 1032 304359;; lower-bound only: indexed counts include tool rows and split content blocks |

**Summary:** 47 PASS, 0 FAIL.
