#!/usr/bin/env python3
"""Build a synthetic HOME with Claude Code, Codex and Pi sessions for demos and screenshots.

Every project, path and conversation here is invented. Timestamps are relative to
now so ages in the UI read naturally (2h, 1d, ...).

Usage: python3 demo/make_demo_home.py <new-dir>
"""

import json
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone

WORK = "/Users/demo/work"

# (harness, project, model, hours_ago, turns)
# turn: ("user", text) | ("asst", text) | ("tool", name, command, output)
SESSIONS = [
    ("claude", "lumen-web", "claude-opus-5", 2, [
        ("user", "The checkout page double-submits when you tap Pay twice on a slow connection."),
        ("asst", "Reproduced with network throttling. The Pay button re-enables before the POST resolves. I'll keep it disabled until the request settles and make the endpoint idempotent with a client key."),
        ("tool", "Bash", "npm test -- checkout", "PASS  src/checkout/checkout.spec.ts (14 tests)"),
        ("user", "Also log a metric when a duplicate is rejected."),
        ("asst", "Added a checkout.duplicate_rejected counter; it increments in the idempotency middleware and shows up on the payments dashboard."),
    ]),
    ("codex", "lumen-api", "gpt-6-sol", 5, [
        ("user", "Plan the orders table migration to add currency without locking writes."),
        ("asst", "Add the column as nullable, backfill in 10k-row batches, then add a NOT NULL check constraint and validate it separately. No table rewrite on Postgres 16."),
        ("tool", "shell", "psql -f migrations/0042_add_currency.sql", "ALTER TABLE"),
        ("asst", "Backfill finished in 4m12s and the constraint validated. Checkout totals now carry the currency code."),
        ("user", "結帳 API 在尖峰時段偶爾逾時，先查原因。"),
        ("asst", "逾時都發生在呼叫付款閘道時，連線池上限只有 10。調到 50 並加上 3 秒逾時與重試後，p99 從 4.2s 降到 380ms。"),
    ]),
    ("pi", "lumen-web", "claude-sonnet-5", 8, [
        ("user", "把 checkout 頁面的錯誤訊息翻成繁體中文，語氣要簡短。"),
        ("asst", "已更新 locales/zh-TW.json：「付款失敗，請再試一次」、「信用卡已過期」、「網路連線中斷」。金額格式改成 NT$1,280。"),
        ("tool", "read", "locales/zh-TW.json", "{ \"checkout.error.failed\": \"付款失敗，請再試一次\" }"),
        ("user", "結帳按鈕的文字也要改。"),
        ("asst", "結帳按鈕改成「確認付款」，英文維持 Pay now。"),
    ]),
    ("claude", "lumen-ingest", "claude-opus-5", 11, [
        ("user", "The ingest worker falls behind every night around 02:00."),
        ("asst", "The nightly export floods the queue while consumer concurrency is fixed at 4. Switched to autoscaling on queue depth with a max of 32."),
        ("tool", "Bash", "go test ./worker/...", "ok  \tlumen/ingest/worker\t1.84s"),
        ("asst", "Queue depth now peaks at 1.2k instead of 48k and drains in under 6 minutes."),
    ]),
    ("codex", "lumen-ios", "gpt-6-luna", 26, [
        ("user", "ログイン画面のエラーメッセージを日本語に翻訳して。"),
        ("asst", "ja の Localizable.strings を追加しました。「パスワードが正しくありません」「ネットワークに接続できません」。"),
        ("user", "Also check that the checkout sheet fits on iPhone SE."),
        ("asst", "It clipped at 568pt; the checkout sheet now scrolls and the Pay button stays pinned to the bottom."),
        ("user", "結帳畫面在 iPhone SE 上的中文字會被截斷嗎？"),
        ("asst", "不會。結帳畫面的標題改用 Dynamic Type，繁中字串在最大字級下也會完整換行；Pay 按鈕固定在底部。"),
    ]),
    ("pi", "lumen-api", "claude-opus-5", 30, [
        ("user", "Add rate limiting to the public search endpoint."),
        ("asst", "Token bucket per API key: 60 requests a minute, burst 20, stored in Redis. Over the limit returns 429 with Retry-After."),
        ("tool", "bash", "go test ./...", "ok  \tlumen/api\t2.31s"),
    ]),
    ("claude", "lumen-docs", "claude-sonnet-5", 44, [
        ("user", "한국어 문서에서 결제 가이드 링크가 깨졌어요."),
        ("asst", "결제 가이드 링크를 /ko/guides/checkout 으로 고쳤고, CI에서 깨진 링크를 검사하도록 했습니다."),
        ("tool", "Bash", "npm run check-links", "0 broken links in 214 pages"),
    ]),
    ("codex", "lumen-web", "gpt-6-sol", 50, [
        ("user", "The checkout e2e test is flaky on CI."),
        ("asst", "It waited a fixed 500ms for the payment iframe. It now waits for the iframe's ready event instead: 50 runs, 0 failures."),
    ]),
    ("pi", "lumen-ingest", "claude-sonnet-5", 70, [
        ("user", "Backfill last month's events after the schema change."),
        ("asst", "Replayed 12.4M events from S3 in 38 minutes. Replays are idempotent by event id, so a rerun is safe."),
    ]),
    ("claude", "lumen-api", "claude-opus-5", 96, [
        ("user", "Migrate auth to the new SDK."),
        ("asst", "Token verification now goes through the new SDK. The old verifier stays behind a flag for one release so we can roll back."),
        ("tool", "Bash", "go test ./auth/...", "ok  \tlumen/api/auth\t0.94s"),
    ]),
    ("codex", "lumen-docs", "gpt-6-luna", 120, [
        ("user", "Draft the release notes for 2.4."),
        ("asst", "Drafted: faster search, Korean docs, checkout fixes, and the new currency column on orders."),
    ]),
    ("pi", "lumen-web", "claude-sonnet-5", 150, [
        ("user", "Dark mode makes the price text unreadable."),
        ("asst", "The price used a hardcoded #333. It now uses the text-primary token; contrast is 12.6:1."),
    ]),
]


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{t.microsecond // 1000:03d}Z"


def write(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def claude(home, sid, cwd, model, times, turns):
    rows, parent = [], None
    for t, turn in zip(times, turns):
        u = str(uuid.uuid4())
        base = {"parentUuid": parent, "isSidechain": False, "sessionId": sid, "cwd": cwd,
                "timestamp": iso(t), "uuid": u, "version": "2.1.0", "gitBranch": "main"}
        if turn[0] == "user":
            rows.append({**base, "type": "user", "message": {"role": "user", "content": turn[1]}})
        elif turn[0] == "asst":
            rows.append({**base, "type": "assistant", "message": {"role": "assistant", "model": model,
                         "content": [{"type": "text", "text": turn[1]}]}})
        else:
            call = "toolu_" + uuid.uuid4().hex[:20]
            rows.append({**base, "type": "assistant", "message": {"role": "assistant", "model": model,
                         "content": [{"type": "tool_use", "id": call, "name": turn[1], "input": {"command": turn[2]}}]}})
            rows.append({**base, "uuid": str(uuid.uuid4()), "type": "user", "message": {"role": "user",
                         "content": [{"type": "tool_result", "tool_use_id": call, "content": turn[3]}]}})
        parent = u
    slug = "-" + cwd.strip("/").replace("/", "-")
    write(f"{home}/.claude/projects/{slug}/{sid}.jsonl", rows)


def codex(home, sid, cwd, model, times, turns):
    t0 = times[0]
    rows = [{"timestamp": iso(t0), "type": "session_meta",
             "payload": {"id": sid, "timestamp": iso(t0), "cwd": cwd, "originator": "codex_cli", "model_provider": "openai"}},
            {"timestamp": iso(t0), "type": "turn_context", "payload": {"cwd": cwd, "model": model}}]
    for t, turn in zip(times, turns):
        if turn[0] in ("user", "asst"):
            role = "user" if turn[0] == "user" else "assistant"
            kind = "input_text" if role == "user" else "output_text"
            rows.append({"timestamp": iso(t), "type": "response_item",
                         "payload": {"type": "message", "role": role, "content": [{"type": kind, "text": turn[1]}]}})
        else:
            call = "call_" + uuid.uuid4().hex[:16]
            rows.append({"timestamp": iso(t), "type": "response_item",
                         "payload": {"type": "function_call", "name": turn[1], "call_id": call,
                                     "arguments": json.dumps({"command": turn[2]})}})
            rows.append({"timestamp": iso(t), "type": "response_item",
                         "payload": {"type": "function_call_output", "call_id": call, "output": turn[3]}})
    d = t0.strftime("%Y/%m/%d")
    write(f"{home}/.codex/sessions/{d}/rollout-{t0.strftime('%Y-%m-%dT%H-%M-%S')}-{sid}.jsonl", rows)


def pi(home, sid, cwd, model, times, turns):
    t0 = times[0]
    rows, parent = [{"type": "session", "version": 3, "id": sid, "timestamp": iso(t0), "cwd": cwd}], None
    for t, turn in zip(times, turns):
        mid = uuid.uuid4().hex[:8]
        if turn[0] == "user":
            msg = {"role": "user", "content": [{"type": "text", "text": turn[1]}]}
        elif turn[0] == "asst":
            msg = {"role": "assistant", "model": model, "content": [{"type": "text", "text": turn[1]}]}
        else:
            rows.append({"type": "message", "id": mid, "parentId": parent, "timestamp": iso(t),
                         "message": {"role": "assistant", "model": model,
                                     "content": [{"type": "toolCall", "id": "tc" + mid, "name": turn[1],
                                                  "arguments": {"command": turn[2]}}]}})
            parent, mid = mid, uuid.uuid4().hex[:8]
            msg = {"role": "toolResult", "toolCallId": "tc" + parent, "toolName": turn[1],
                   "content": [{"type": "text", "text": turn[3]}]}
        rows.append({"type": "message", "id": mid, "parentId": parent, "timestamp": iso(t), "message": msg})
        parent = mid
    slug = "--" + cwd.strip("/").replace("/", "-") + "--"
    write(f"{home}/.pi/agent/sessions/{slug}/{t0.strftime('%Y-%m-%dT%H-%M-%S-000Z')}_{sid}.jsonl", rows)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    home = sys.argv[1]
    if os.path.exists(home):
        sys.exit(f"refusing to overwrite existing path: {home}")
    now = datetime.now(timezone.utc).replace(microsecond=0)
    writers = {"claude": claude, "codex": codex, "pi": pi}
    for harness, project, model, hours, turns in SESSIONS:
        start = now - timedelta(hours=hours)
        times = [start + timedelta(minutes=2 * i) for i in range(len(turns))]
        writers[harness](home, str(uuid.uuid4()), f"{WORK}/{project}", model, times, turns)
    print(home)


if __name__ == "__main__":
    main()
