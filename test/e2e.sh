#!/bin/bash
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); TEST="$ROOT/test"; BIN="$ROOT/hindsight"; REALHOME_DEFAULT=$HOME
REPORT="$TEST/e2e-report.md"; SCREENS="$TEST/screens"; mkdir -p "$SCREENS"
printf '# E2E report\n\nRun: %s\n\n| Check | Result | Time | Details |\n|---|---:|---:|---|\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$REPORT"
PASS=0; FAIL=0
: > "$TEST/BUGS.md"
record(){ local name=$1 res=$2 sec=$3 detail=${4:-} expected='check passes per test/FAILURE_MODES.md' repro='test/e2e.sh'; detail=${detail//|/\\|}; detail=${detail//$'\n'/ }; printf '| %s | %s | %ss | %s |\n' "$name" "$res" "$sec" "$detail" >> "$REPORT"; if [[ $res == PASS ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); if [[ $name == Performance:* ]]; then expected='p95 over 20 varied query latencies is <= 200ms'; repro='test/e2e.sh (200k-message fixture)'; fi; if [[ $name == Hit-list* ]]; then expected='each clipped hit snippet ends with ellipsis and no Latin word is cut'; fi; failbug "$name" "$repro" "$expected" "$detail"; fi; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hindsight-e2e.XXXXXX")
cleanup(){ tmux kill-session -t "htrunc-$$" 2>/dev/null || :; tmux kill-session -t "he2e-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-codex-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-pi-$$" 2>/dev/null || :; tmux kill-session -t "hedt-$$" 2>/dev/null || :; rm -rf "$TMP"; }
trap cleanup EXIT
failbug(){ printf '\n- **%s**\n  - Repro: `%s`\n  - Expected: %s\n  - Actual: %s\n' "$1" "$2" "$3" "$4" >> "$TEST/BUGS.md"; }

# Build phase
start=$SECONDS; (cd "$ROOT" && make build) >"$SCREENS/build.txt" 2>&1; rc=$?; if ((rc==0)); then record 'make build (sqlite_fts5)' PASS $((SECONDS-start)) 'built ./hindsight'; else record 'make build (sqlite_fts5)' FAIL $((SECONDS-start)) "$(<"$SCREENS/build.txt")"; fi

H="$TMP/home"; "$TEST/fixture.sh" "$H" >/dev/null || exit 1
mkdir -p "$H/work/demo" "$H/index"
python3 - "$H" <<'PY'
import pathlib,sys
h=pathlib.Path(sys.argv[1])
for p in h.rglob('*.jsonl'):
 p.write_text(p.read_text().replace('/work/demo',str(h/'work/demo')))
PY
export HOME="$H" HINDSIGHT_INDEX="$H/index/index.db" HINDSIGHT_THEME=light TERM=xterm-256color

start=$SECONDS; out=$("$BIN" index --rebuild 2>&1); rc=$?
if ((rc==0)) && grep -q 'claude: 5 messages' <<<"$out" && grep -q 'codex: 5 messages' <<<"$out" && grep -q 'pi: 5 messages' <<<"$out" && grep -q '3 files, 3 changed, 0 skipped' <<<"$out"; then record 'Index Claude/Codex/Pi real-format fixtures' PASS $((SECONDS-start)) "$out"; else record 'Index Claude/Codex/Pi real-format fixtures' FAIL $((SECONDS-start)) "$out"; fi
start=$SECONDS; before=$(shasum "$H"/.claude/projects/*/*.jsonl "$H"/.codex/sessions/*/*/*/*.jsonl "$H"/.pi/agent/sessions/*/*.jsonl); out=$("$BIN" index 2>&1); rc=$?; after=$(shasum "$H"/.claude/projects/*/*.jsonl "$H"/.codex/sessions/*/*/*/*.jsonl "$H"/.pi/agent/sessions/*/*.jsonl)
if ((rc==0)) && grep -q '0 changed' <<<"$out" && [[ $before == "$after" ]]; then record 'No-op incremental scan; transcript bytes unchanged' PASS $((SECONDS-start)) "$out"; else record 'No-op incremental scan; transcript bytes unchanged' FAIL $((SECONDS-start)) "$out"; fi
# New, modified, and deleted sources must sync without duplicate rows.
orig=$(echo "$H"/.claude/projects/*/*.jsonl); clone="$H/.claude/projects/-work-demo/44444444-4444-4444-8444-444444444444.jsonl"
python3 - "$orig" "$clone" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text().replace('11111111-1111-4111-8111-111111111111','44444444-4444-4444-8444-444444444444')
s += '{"type":"user","message":{"role":"user","content":"Added syncmarker."},"timestamp":"2026-09-27T10:20:00Z","cwd":"/work/demo","sessionId":"44444444-4444-4444-8444-444444444444"}\n'
pathlib.Path(sys.argv[2]).write_text(s)
PY
start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; if ((rc==0)) && grep -q '4 files, 1 changed' <<<"$out" && grep -q 'claude: 11 messages' <<<"$out"; then record 'Incremental sync adds new file' PASS $((SECONDS-start)) "$out"; else record 'Incremental sync adds new file' FAIL $((SECONDS-start)) "$out"; fi
python3 - "$clone" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace('syncmarker','syncchange'))
PY
start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; changed=$("$BIN" --json syncchange 2>&1); if ((rc==0)) && grep -q '4 files, 1 changed' <<<"$out" && grep -q syncchange <<<"$changed" && [[ $(grep -c '"session_id":"44444444' <<<"$changed") == 1 ]]; then record 'Changed source is replaced, not duplicated' PASS $((SECONDS-start)) "$out"; else record 'Changed source is replaced, not duplicated' FAIL $((SECONDS-start)) "$out $changed"; fi
rm "$clone"; start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; removed=$("$BIN" --json syncchange 2>&1); if ((rc==0)) && grep -q 'claude: 5 messages' <<<"$out" && [[ -z $removed ]]; then record 'Deleted source is removed from index' PASS $((SECONDS-start)) "$out"; else record 'Deleted source is removed from index' FAIL $((SECONDS-start)) "$out $removed"; fi

# Query correctness cases from SPEC's Expected behavior plus languages/filters.
check_query(){ local q=$1 mode=$2 want=${3:-}; local t=$SECONDS out rc; out=$("$BIN" --json "$q" 2>&1); rc=$?; local ok=1
 if ((rc)); then ok=0; elif [[ $mode == empty ]]; then [[ -z $out ]] || ok=0; elif ! grep -Fq "$want" <<<"$out"; then ok=0; fi
 if ((ok)); then record "query: $q ($mode)" PASS $((SECONDS-t)) ''; else record "query: $q ($mode)" FAIL $((SECONDS-t)) "expected $mode $want; got: $out"; failbug "Query $q" "HOME=$HOME HINDSIGHT_INDEX=$HINDSIGHT_INDEX ./hindsight --json '$q'" "${mode} ${want}" "$out"; fi
}
check_query snapshot contains SNAPSHOT
check_query recoverytoken contains recoverytoken
check_query resum contains resuming
check_query sume empty
check_query '"tea black"' empty
check_query naive contains 'naïve'
for q in json_extract low-water S3 cjk.c; do check_query "$q" contains "$q"; done
check_query 魚池 contains 魚池
check_query 南投魚池 empty
check_query 茶 contains 茶
check_query 日本語 contains 日本語
check_query 한국어 contains 한국어
check_query --flag empty
start=$SECONDS; version=$("$BIN" --version 2>&1); rc=$?; if ((rc==0)) && [[ -n $version ]]; then record 'CLI --version' PASS $((SECONDS-start)) "$version"; else record 'CLI --version' FAIL $((SECONDS-start)) "$version"; fi
start=$SECONDS; recent=$("$BIN" --json 2>&1); rc=$?; if ((rc==0)) && [[ -n $recent ]] && printf '%s\n' "$recent" | jq -se 'all(.[]; has("session_id") and has("text"))' >/dev/null 2>&1; then record 'Empty query lists recent messages as JSONL' PASS $((SECONDS-start)) "$(printf '%s\n' "$recent" | wc -l | tr -d ' ') rows"; else record 'Empty query lists recent messages as JSONL' FAIL $((SECONDS-start)) "$recent"; fi
start=$SECONDS; malformed=$("$BIN" --json '"' 2>&1); rc=$?; if ((rc==0)) && { [[ -z $malformed ]] || printf '%s\\n' "$malformed" | jq -e . >/dev/null 2>&1; }; then record 'Malformed quote query does not crash' PASS $((SECONDS-start)) ''; else record 'Malformed quote query does not crash' FAIL $((SECONDS-start)) "$malformed"; fi

start=$SECONDS; out=$("$BIN" --json snapshot 2>&1); rc=$?; printf '%s\n' "$out" > "$SCREENS/json-snapshot.jsonl"
if ((rc==0)) && printf '%s\n' "$out" | jq -se 'all(.[]; ([keys[]]|sort)==(["harness","session_id","project","cwd","ts","role","text","snippet","resume_cmd","path"]|sort))' >/dev/null; then record 'JSONL parse/schema: all required fields' PASS $((SECONDS-start)) "$(wc -l < "$SCREENS/json-snapshot.jsonl") rows"; else record 'JSONL parse/schema: all required fields' FAIL $((SECONDS-start)) "$out"; fi
for h in claude codex pi; do start=$SECONDS; out=$("$BIN" --json --harness "$h" snapshot 2>&1); rc=$?; if ((rc==0)) && [[ -n $out ]] && ! grep -Ev '"harness":"'"$h"'"' <<<"$out" | grep -q .; then record "JSON harness filter $h" PASS $((SECONDS-start)) ''; else record "JSON harness filter $h" FAIL $((SECONDS-start)) "$out"; fi; done

# Long Latin hits exercise snippet clipping in each agent's hit-list row.
python3 - "$H" <<'PY'
import glob,json,pathlib,sys
h=pathlib.Path(sys.argv[1]); text='cutprobe alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu supercalifragilisticexpialidocious tail'
claude=glob.glob(str(h/'.claude/projects/*/*.jsonl'))[0]
with open(claude,'a') as f: f.write(json.dumps({'type':'user','uuid':'11111111-1111-4111-8111-111111111106','timestamp':'2026-09-27T10:30:00Z','cwd':str(h/'work/demo'),'sessionId':'11111111-1111-4111-8111-111111111111','message':{'role':'user','content':text}},ensure_ascii=False)+'\n')
codex=glob.glob(str(h/'.codex/sessions/**/*.jsonl'),recursive=True)[0]
with open(codex,'a') as f: f.write(json.dumps({'timestamp':'2026-09-27T10:30:00Z','type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':text}]}},ensure_ascii=False)+'\n')
pi=glob.glob(str(h/'.pi/agent/sessions/*/*.jsonl'))[0]
with open(pi,'a') as f: f.write(json.dumps({'type':'message','id':'33333333-3333-4333-8333-333333333306','parentId':'33333333-3333-4333-8333-333333333305','timestamp':'2026-09-27T10:30:00Z','message':{'role':'user','content':[{'type':'text','text':text}]}},ensure_ascii=False)+'\n')
PY
# Real TUI via tmux. Plain and escape-preserving captures are retained for inspection.
tmux set-option -g remain-on-exit on 2>/dev/null || :
export HINDSIGHT_INDEX="$H/index/tui.db"
tmux new-session -d -x 120 -y 40 -s "he2e-$$" "cd '$ROOT' && HOME='$HOME' HINDSIGHT_INDEX='$HINDSIGHT_INDEX' HINDSIGHT_THEME=light TERM=xterm-256color exec ./hindsight snapshot" 2>/dev/null
sleep 1
tmux capture-pane -t "he2e-$$" -p > "$SCREENS/tui-start.txt" 2>&1; tmux capture-pane -t "he2e-$$" -ep > "$SCREENS/tui-start-ansi.txt" 2>&1
start=$SECONDS; if grep -q 'SNAPSHOT' "$SCREENS/tui-start.txt"; then record 'TUI starts and displays matching hit' PASS $((SECONDS-start)) ''; else record 'TUI starts and displays matching hit' FAIL $((SECONDS-start)) "$(<"$SCREENS/tui-start.txt")"; fi
if grep -q $'\033\[2m' "$SCREENS/tui-start-ansi.txt"; then record 'Unfocused zone dimming (SGR 2)' PASS 0 ''; else record 'Unfocused zone dimming (SGR 2)' FAIL 0 'no SGR 2 in capture'; fi
if grep -Fq '38;2;182;50;44' "$SCREENS/tui-start-ansi.txt"; then record 'Hit color present in ANSI capture' PASS 0 ''; else record 'Hit color present in ANSI capture' FAIL 0 'red hit pen not found in escape capture'; fi
# Escape to results, enable full transcript, check folded/full render, then add a pen.
tmux send-keys -t "he2e-$$" Escape; sleep .3; tmux capture-pane -t "he2e-$$" -p > "$SCREENS/tui-folded.txt"
tmux send-keys -t "he2e-$$" v; sleep .2; tmux capture-pane -t "he2e-$$" -p > "$SCREENS/tui-full.txt"
if grep -q '⋯' "$SCREENS/tui-folded.txt"; then record 'Transcript folding ellipsis ⋯' PASS 0 ''; else record 'Transcript folding ellipsis ⋯' FAIL 0 'not visible'; fi
if grep -q 'Fish pond\|魚池\|tea' "$SCREENS/tui-full.txt"; then record 'Full mode reveals non-hit transcript content' PASS 0 ''; else record 'Full mode reveals non-hit transcript content' FAIL 0 'expected transcript text missing'; fi
tmux send-keys -t "he2e-$$" v; sleep .15; tmux send-keys -t "he2e-$$" h; sleep .2; tmux send-keys -l -t "he2e-$$" snapshot; tmux send-keys -t "he2e-$$" Enter; sleep .3; tmux capture-pane -t "he2e-$$" -ep > "$SCREENS/tui-pen-ansi.txt"
if grep -Fq '48;2;253;232;154' "$SCREENS/tui-pen-ansi.txt"; then record 'Highlight pen background color' PASS 0 ''; else record 'Highlight pen background color' FAIL 0 'pen color not found'; fi
# Ctrl-C exits UI; tmux remains-on-exit lets us assert the process is dead.
tmux send-keys -t "he2e-$$" C-c; sleep .5; tmux capture-pane -t "he2e-$$" -p > "$SCREENS/tui-after-ctrl-c.txt" 2>&1; state=$(tmux display-message -p -t "he2e-$$" '#{pane_dead}' 2>/dev/null || echo yes)
if [[ $state == 1 ]] && ! grep -q 'hindsight ▸' "$SCREENS/tui-after-ctrl-c.txt"; then record 'Ctrl-C exits and restores terminal (process + alternate screen)' PASS 0 ''; else record 'Ctrl-C exits and restores terminal (process exits)' FAIL 0 "pane_dead=$state"; fi

# Stub agents and editor: assert exec argv/cwd and detached editor arguments.
STUB="$TMP/stub"; mkdir -p "$STUB"; export STUBLOG="$TMP/stub.log"
for tool in claude codex pi zed; do cat > "$STUB/$tool" <<'SH'
#!/bin/sh
printf '%s|%s|%s\n' "$(basename "$0")" "$PWD" "$*" >> "$STUBLOG"
SH
chmod +x "$STUB/$tool"; done
export PATH="$STUB:$PATH"
# Resume Claude: execute stub in real synthetic cwd after selecting the first hit.
export HINDSIGHT_INDEX="$H/index/resume.db"
tmux new-session -d -x 100 -y 32 -s "hrsm-$$" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' HINDSIGHT_INDEX='$HINDSIGHT_INDEX' TERM=xterm-256color exec ./hindsight --harness claude snapshot" 2>/dev/null
sleep 1; tmux send-keys -t "hrsm-$$" Escape; sleep .2; tmux send-keys -t "hrsm-$$" Enter; sleep .8
CWD_PHYS=$(cd "$H/work/demo" && pwd -P)
if grep -Fq "claude|$CWD_PHYS|--resume 11111111-1111-4111-8111-111111111111" "$STUBLOG" 2>/dev/null; then record 'Resume Claude stub argv + cwd' PASS 0 "$(tail -1 "$STUBLOG")"; else record 'Resume Claude stub argv + cwd' FAIL 0 "$(cat "$STUBLOG" 2>/dev/null || echo no stub call)"; fi
# Codex and Pi use their harness-specific resume forms too.
for harness in codex pi; do
  session="hrsm-$harness-$$"; export HINDSIGHT_INDEX="$H/index/resume-$harness.db"
  tmux new-session -d -x 100 -y 32 -s "$session" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' HINDSIGHT_INDEX='$HINDSIGHT_INDEX' TERM=xterm-256color exec ./hindsight --harness $harness snapshot" 2>/dev/null
  sleep 1; tmux send-keys -t "$session" Escape; sleep .2; tmux send-keys -t "$session" Enter; sleep .6
  if [[ $harness == codex ]]; then expected="codex|$CWD_PHYS|resume 22222222-2222-4222-8222-222222222222"; else pi_path=$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$H/.pi/agent/sessions/-work-demo/33333333-3333-4333-8333-333333333333.jsonl"); expected="pi|$CWD_PHYS|--session $pi_path"; fi
  if grep -Fq "$expected" "$STUBLOG" 2>/dev/null; then record "Resume $harness stub argv + cwd" PASS 0 "$expected"; else record "Resume $harness stub argv + cwd" FAIL 0 "expected $expected; log: $(cat "$STUBLOG" 2>/dev/null)"; fi
done
# Editor configuration takes precedence and receives project cwd while TUI survives.
export HINDSIGHT_INDEX="$H/index/editor.db" HINDSIGHT_EDITOR="$STUB/zed"
tmux new-session -d -x 100 -y 32 -s "hedt-$$" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' HINDSIGHT_EDITOR='$HINDSIGHT_EDITOR' HINDSIGHT_INDEX='$HINDSIGHT_INDEX' TERM=xterm-256color exec ./hindsight snapshot" 2>/dev/null
sleep 1; tmux send-keys -t "hedt-$$" Escape; sleep .2; tmux send-keys -t "hedt-$$" o; sleep .5
if grep -Fq 'zed|' "$STUBLOG" 2>/dev/null && grep -Fq 'work/demo' "$STUBLOG" 2>/dev/null; then record 'Editor stub launch + project directory' PASS 0 "$(tail -1 "$STUBLOG")"; else record 'Editor stub launch + project directory' FAIL 0 "zed not launched with project directory; log=$(cat "$STUBLOG" 2>/dev/null)"; fi
tmux capture-pane -t "hedt-$$" -p > "$SCREENS/tui-editor.txt" 2>&1
if tmux has-session -t "hedt-$$" 2>/dev/null; then record 'Editor launch leaves TUI alive' PASS 0 ''; else record 'Editor launch leaves TUI alive' FAIL 0 'TUI exited'; fi

tmux kill-session -t "hedt-$$" 2>/dev/null || :
# Truncation test has a hit crossing a Latin word at the snippet's right boundary.
export HINDSIGHT_INDEX="$H/index/trunc.db"
tmux new-session -d -x 120 -y 40 -s "htrunc-$$" "cd '$ROOT' && HOME='$HOME' HINDSIGHT_INDEX='$HINDSIGHT_INDEX' HINDSIGHT_THEME=light TERM=xterm-256color exec ./hindsight cutprobe" 2>/dev/null
sleep 1; tmux capture-pane -t "htrunc-$$" -p > "$SCREENS/tui-truncation.txt" 2>&1
python3 - "$SCREENS/tui-truncation.txt" <<'PY' > "$TMP/truncation-check.txt"
import sys
rows=[x.rstrip('\\n') for x in open(sys.argv[1],encoding='utf8') if '▌ cutprobe' in x]
errors=[]
if len(rows)!=3: errors.append(f'expected 3 hit rows, found {len(rows)}')
for row in rows:
 agents=[(row.rfind('claude'),'claude'),(row.rfind('codex'),'codex'),(row.rfind('pi'),'pi')]
 pos,agent=max((x for x in agents if x[0]>=0),default=(-1,''))
 snippet=row[:pos].rstrip() if pos>=0 else row
 if not snippet.endswith('…'): errors.append(f'{agent} hit row has no trailing ellipsis: {row}')
 token='supercalifragilisticexpialidocious'
 if token[:12] in snippet and token not in snippet: errors.append(f'{agent} row cuts Latin token: {row}')
print('\\n'.join(errors) if errors else '3 hit rows end their clipped snippet in ellipsis; Latin token intact or omitted')
sys.exit(bool(errors))
PY
if [[ ! -s "$TMP/truncation-check.txt" ]] || ! grep -q 'expected\|no trailing\|cuts Latin' "$TMP/truncation-check.txt"; then record 'Hit-list truncation: ellipsis + whole Latin words' PASS 0 "$(<"$TMP/truncation-check.txt")"; else record 'Hit-list truncation: ellipsis + whole Latin words' FAIL 0 "$(<"$TMP/truncation-check.txt")"; fi
tmux kill-session -t "htrunc-$$" 2>/dev/null || :

# Large fixture: 2,000 Codex sessions x 100 user/assistant pairs = 200,000 messages.
PERF="$TMP/perfhome"; mkdir -p "$PERF"; export PERF
python3 - <<'PY'
import json,os,pathlib
root=pathlib.Path(os.environ['PERF'])/'.codex/sessions/2026/09/27'; root.mkdir(parents=True)
for i in range(2000):
 p=root/f'rollout-{i:04}.jsonl'; sid=f'{i:032x}'
 with p.open('w') as f:
  f.write(json.dumps({'timestamp':'2026-09-27T10:00:00Z','type':'session_meta','payload':{'id':sid,'cwd':'/work/perf'}})+'\n')
  for j in range(100):
   role='user' if j%2==0 else 'assistant'; typ='input_text' if role=='user' else 'output_text'
   text='perfneedle large fixture message 魚池 紅茶 日本語 한국어' if j==0 else f'neutral synthetic message {j}'
   f.write(json.dumps({'timestamp':'2026-09-27T10:00:01Z','type':'response_item','payload':{'type':'message','role':role,'content':[{'type':typ,'text':text}]}})+'\n')
PY
export HOME="$PERF" HINDSIGHT_INDEX="$TMP/perf.db"
python3 - "$BIN" "$TMP/perf-metrics.json" <<'PY'
import json,math,os,statistics,subprocess,sys,time
binary,outfile=sys.argv[1:]; env=os.environ.copy(); env['HINDSIGHT_DEBUG_TIMING']='1'
t=time.perf_counter_ns(); index=subprocess.run([binary,'index','--rebuild'],env=env,text=True,capture_output=True); index_ms=(time.perf_counter_ns()-t)/1e6
queries=['perfneedle','synthetic','neutral','"large fixture"','"synthetic message"','-perfneedle','large','fixture','message','neutral 42','neutral 17','魚池','紅茶','日本語','한국어','perfneed','"neutral synthetic"','-neutral','"fixture message"','absenttoken']
latencies=[]; failures=[]; results=[]; samples=[]
for q in queries:
 t=time.perf_counter_ns(); p=subprocess.run([binary,'--json',q],env=env,text=True,capture_output=True); elapsed=(time.perf_counter_ns()-t)/1e6; latencies.append(elapsed)
 if p.returncode: failures.append({'query':q,'error':p.stderr.strip()})
 results.append(sum(1 for x in p.stdout.splitlines() if x.strip())); samples.append({'query':q,'ms':round(elapsed,2),'timing':p.stderr.strip().replace('\\n','; ')})
sorted_ms=sorted(latencies); p95=sorted_ms[math.ceil(.95*len(sorted_ms))-1]
json.dump({'index_rc':index.returncode,'index_out':index.stdout+index.stderr,'index_ms':round(index_ms,2),'n':len(latencies),'median_ms':round(statistics.median(latencies),2),'p95_ms':round(p95,2),'failures':failures,'results':results,'slowest':sorted(samples,key=lambda x:x['ms'],reverse=True)[:3]},open(outfile,'w'))
PY
metrics=$(<"$TMP/perf-metrics.json"); index_ms=$(jq -r .index_ms <<<"$metrics"); median_ms=$(jq -r .median_ms <<<"$metrics"); p95_ms=$(jq -r .p95_ms <<<"$metrics"); failures=$(jq -r '.failures|length' <<<"$metrics"); index_rc=$(jq -r .index_rc <<<"$metrics"); details="index=${index_ms}ms queries=$(jq -r .n <<<"$metrics") median=${median_ms}ms p95=${p95_ms}ms slowest=$(jq -c .slowest <<<"$metrics")"
if ((index_rc==0 && failures==0)) && grep -q '200000 messages' <<<"$(jq -r .index_out <<<"$metrics")" && awk -v p="$p95_ms" 'BEGIN{exit !(p<=200)}'; then record 'Performance: 2k sessions / 200k messages (20 varied queries)' PASS 0 "$details"; else record 'Performance: 2k sessions / 200k messages (20 varied queries)' FAIL 0 "$details; index_rc=$index_rc query_failures=$failures $(jq -r .index_out <<<"$metrics")"; fi

# Appends (including an incomplete final record) must be ingested without rebuilding the corpus.
append_file="$PERF/.codex/sessions/2026/09/27/rollout-0000.jsonl"
python3 - "$append_file" "$TMP/partial-rest" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); full=json.dumps({'timestamp':'2026-09-27T12:00:00Z','type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':'appendtoken now searchable'}]}}).encode()+b'\n'
with p.open('ab') as f: f.write(full)
partial=json.dumps({'timestamp':'2026-09-27T12:01:00Z','type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':'partialtoken completed later'}]}}).encode()
with p.open('ab') as f: f.write(partial[:-1])
pathlib.Path(sys.argv[2]).write_bytes(partial[-1:]+b'\n')
PY
start=$SECONDS; appended=$(HINDSIGHT_DEBUG_TIMING=1 "$BIN" --json appendtoken 2>"$TMP/append-timing.txt"); append_rc=$?; append_ms=$(sed -nE 's/^timing sync_changes=([0-9.]+)ms$/\1/p' "$TMP/append-timing.txt"); after_append=$("$BIN" index 2>&1)
if ((append_rc==0)) && grep -q appendtoken <<<"$appended" && grep -q 'codex: 200001 messages' <<<"$after_append" && grep -q '0 changed' <<<"$after_append" && [[ -n $append_ms ]] && awk -v x="$append_ms" 'BEGIN{exit !(x<200)}'; then record 'Append sync: next CLI query finds new line; only tail parsed' PASS $((SECONDS-start)) "sync_changes=${append_ms}ms; $after_append"; else record 'Append sync: next CLI query finds new line; only tail parsed' FAIL $((SECONDS-start)) "query=$appended timing=$(cat "$TMP/append-timing.txt") index=$after_append"; fi
partial=$(HINDSIGHT_DEBUG_TIMING=1 "$BIN" --json partialtoken 2>"$TMP/partial-timing.txt"); partial_rc=$?; if ((partial_rc==0)) && [[ -z $partial ]]; then record 'Partial final line is withheld until newline' PASS 0 "$(cat "$TMP/partial-timing.txt")"; else record 'Partial final line is withheld until newline' FAIL 0 "unexpected query output: $partial"; fi
cat "$TMP/partial-rest" >> "$append_file"; completed=$("$BIN" --json partialtoken 2>&1); complete_index=$("$BIN" index 2>&1)
if grep -q partialtoken <<<"$completed" && grep -q 'codex: 200002 messages' <<<"$complete_index" && grep -q '0 changed' <<<"$complete_index"; then record 'Partial line is re-read and indexed when completed' PASS 0 "$complete_index"; else record 'Partial line is re-read and indexed when completed' FAIL 0 "query=$completed index=$complete_index"; fi

# Independent read-only real-store count versus app indexing with an isolated DB.
REALHOME="$REALHOME_DEFAULT"; REALTMP="$TMP/real"; mkdir -p "$REALTMP"; export REALHOME REALTMP
python3 - <<'PY' > "$REALTMP/independent.txt"
import glob,json,os
home=os.environ['REALHOME']
patterns={'claude':home+'/.claude/projects/**/*.jsonl','codex':home+'/.codex/sessions/**/*.jsonl','pi':home+'/.pi/agent/sessions/**/*.jsonl'}
for h,pat in patterns.items():
 files=glob.glob(pat,recursive=True); n=0
 for p in files:
  try:
   for line in open(p,encoding='utf8'):
    try:d=json.loads(line)
    except:continue
    m=d.get('message') or {}; payload=d.get('payload') or {}
    if h=='claude' and d.get('type') in ('user','assistant') and not d.get('isMeta') and not d.get('isSidechain'):
     c=m.get('content',''); n+=bool(c) if isinstance(c,str) else any(x.get('type')=='text' and x.get('text') for x in c if isinstance(x,dict))
    elif h=='codex' and d.get('type')=='response_item' and payload.get('type')=='message' and payload.get('role') in ('user','assistant'):
     n+=sum(bool(x.get('text')) for x in payload.get('content',[]) if isinstance(x,dict) and x.get('type') in ('input_text','output_text'))
    elif h=='pi' and d.get('type')=='message' and m.get('role') in ('user','assistant'):
     c=m.get('content',[]); n+=bool(c) if isinstance(c,str) else sum(bool(x.get('text')) for x in c if isinstance(x,dict) and x.get('type')=='text')
  except (OSError,UnicodeError): pass
 print(h,len(files),n)
PY
export HOME="$REALHOME" HINDSIGHT_INDEX="$REALTMP/index.db"
start=$SECONDS; realout=$("$BIN" index --rebuild 2>&1); rc=$?; python3 - "$REALTMP/independent.txt" "$REALTMP/app.txt" <<'PY'
import sqlite3,sys
rows=sqlite3.connect(sys.argv[2].replace('app.txt','index.db')).execute('select harness,count(distinct uid),sum((select count(*) from messages m where m.session_uid=s.uid)) from sessions s group by harness').fetchall()
open(sys.argv[2],'w').write('\n'.join('%s %s %s'%r for r in rows)+'\n')
PY
{ printf 'independent: harness total_jsonl raw_user_assistant_text_blocks\n'; cat "$REALTMP/independent.txt"; printf 'indexed: harness sessions message_rows\n'; cat "$REALTMP/app.txt"; } > "$SCREENS/real-store-counts.txt"
# Raw user/assistant text blocks are a conservative lower bound: indexed rows also include tools.
if ((rc==0)) && python3 - "$REALTMP/independent.txt" "$REALTMP/app.txt" <<'PY'
import sys
ind={x.split()[0]:int(x.split()[2]) for x in open(sys.argv[1])}; app={x.split()[0]:int(x.split()[2]) for x in open(sys.argv[2])}
for h,n in ind.items():
 a=app.get(h,0)
 if n and a<n: print(f'{h}: indexed={a} below independent user/assistant lines={n}'); sys.exit(1)
 if n and not a: print(f'{h}: independent={n}, indexed=0'); sys.exit(1)
PY
then record 'Real stores: read-only independent lower-bound sanity' PASS $((SECONDS-start)) "$(tr '\n' ';' < "$SCREENS/real-store-counts.txt"); lower-bound only: indexed counts include tool rows and split content blocks"; else record 'Real stores: read-only independent lower-bound sanity' FAIL $((SECONDS-start)) "$realout; $(tr '\n' ';' < "$SCREENS/real-store-counts.txt")"; failbug 'Real store message undercount' 'HINDSIGHT_INDEX=<temp>/index.db ./hindsight index --rebuild; compare to test/screens/real-store-counts.txt' 'indexed rows >= independent user/assistant text blocks' "$realout; see test/screens/real-store-counts.txt"; fi

printf '\n**Summary:** %d PASS, %d FAIL.\n' "$PASS" "$FAIL" >> "$REPORT"
printf '%d PASS / %d FAIL — report: test/e2e-report.md\n' "$PASS" "$FAIL"
((FAIL==0))
