#!/bin/bash
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); TEST="$ROOT/test"; BIN="$ROOT/kioku"; REALHOME_DEFAULT=$HOME
REPORT="$TEST/e2e-report.md"; SCREENS="$TEST/screens"; mkdir -p "$SCREENS"
printf '# E2E report\n\nRun: %s\n\n| Check | Result | Time | Details |\n|---|---:|---:|---|\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$REPORT"
PASS=0; FAIL=0
: > "$TEST/BUGS.md"
record(){ local name=$1 res=$2 sec=$3 detail=${4:-} expected='check passes per test/FAILURE_MODES.md' repro='test/e2e.sh'; detail=${detail//|/\\|}; detail=${detail//$'\n'/ }; printf '| %s | %s | %ss | %s |\n' "$name" "$res" "$sec" "$detail" >> "$REPORT"; if [[ $res == PASS ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); if [[ $name == Performance:* ]]; then expected='p95 over 20 varied query latencies is <= 200ms'; repro='test/e2e.sh (200k-message fixture)'; fi; if [[ $name == Hit-list* ]]; then expected='each clipped hit snippet ends with ellipsis and no Latin word is cut'; fi; if [[ $name == Search\ semantics:* ]]; then expected='common-word results include the newest Claude message and results outside the last-indexed Pi file'; fi; failbug "$name" "$repro" "$expected" "$detail"; fi; }
skip(){ printf '| %s | SKIP | 0s | %s |\n' "$1" "$2" >> "$REPORT"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kioku-e2e.XXXXXX")
cleanup(){ tmux kill-session -t "htool-$$" 2>/dev/null || :; tmux kill-session -t "htrunc-$$" 2>/dev/null || :; tmux kill-session -t "he2e-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-codex-$$" 2>/dev/null || :; tmux kill-session -t "hrsm-pi-$$" 2>/dev/null || :; tmux kill-session -t "hedt-$$" 2>/dev/null || :; rm -rf "$TMP"; }
trap cleanup EXIT
failbug(){ printf '\n- **%s**\n  - Repro: `%s`\n  - Expected: %s\n  - Actual: %s\n' "$1" "$2" "$3" "$4" >> "$TEST/BUGS.md"; }

# Build phase
start=$SECONDS; (cd "$ROOT" && make build) >"$SCREENS/build.txt" 2>&1; rc=$?; if ((rc==0)); then record 'make build (sqlite_fts5)' PASS $((SECONDS-start)) 'built ./kioku'; else record 'make build (sqlite_fts5)' FAIL $((SECONDS-start)) "$(<"$SCREENS/build.txt")"; fi

H="$TMP/home"; "$TEST/fixture.sh" "$H" >/dev/null || exit 1
mkdir -p "$H/work/demo" "$H/index"
python3 - "$H" <<'PY'
import pathlib,sys
h=pathlib.Path(sys.argv[1])
for p in h.rglob('*.jsonl'):
 p.write_text(p.read_text().replace('/work/demo',str(h/'work/demo')))
PY
export HOME="$H" KIOKU_INDEX="$H/index/index.db" KIOKU_THEME=light TERM=xterm-256color

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
start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; changed=$("$BIN" --json syncchange 2>&1); if ((rc==0)) && grep -q '4 files, 1 changed' <<<"$out" && jq -e '.total==1 and (.hits|length)==1 and (.hits[0].snippet|contains("syncchange"))' <<<"$changed" >/dev/null; then record 'Changed source is replaced, not duplicated' PASS $((SECONDS-start)) "$out"; else record 'Changed source is replaced, not duplicated' FAIL $((SECONDS-start)) "$out $changed"; fi
rm "$clone"; start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; removed=$("$BIN" --json syncchange 2>&1); if ((rc==0)) && grep -q 'claude: 5 messages' <<<"$out" && jq -e '.total==0 and .shown==0 and (.hits|length)==0' <<<"$removed" >/dev/null; then record 'Deleted source is removed from index' PASS $((SECONDS-start)) "$out"; else record 'Deleted source is removed from index' FAIL $((SECONDS-start)) "$out $removed"; fi
# Short prefixes report omitted older messages; --all-time restores them.
if python3 - "$BIN" "$TMP/short-prefix" <<'PY' > "$TMP/short-prefix.txt" 2> "$TMP/short-prefix.err"
import json,os,pathlib,subprocess,sys
binary,root=sys.argv[1:]; root=pathlib.Path(root)
sessions=root/'.pi/agent/sessions/demo'; sessions.mkdir(parents=True)
for sid,dates in [('old',['2026-01-01T00:00:00Z','2026-01-02T00:00:00Z']),('recent',['2026-01-25T00:00:00Z','2026-02-01T00:00:00Z'])]:
 rows=[{'type':'session','version':3,'id':sid,'timestamp':dates[0],'cwd':'/work/demo'}]
 rows += [{'type':'message','id':f'{sid}-{i}','timestamp':date,'message':{'role':'user','content':[{'type':'text','text':f'qw qword {sid} match {i}'}]}} for i,date in enumerate(dates)]
 (sessions/f'{sid}.jsonl').write_text('\n'.join(json.dumps(r) for r in rows)+'\n')
env=os.environ.copy(); env.update(HOME=str(root),KIOKU_INDEX=str(root/'index.db'))
def run(*args):
 p=subprocess.run([binary,*args],env=env,text=True,capture_output=True)
 assert p.returncode==0, p.stderr
 return p.stdout
for query in ['q','qw']:
 for mode in [[],['--sessions']]:
  page=json.loads(run('--json',*mode,query))
  assert page['total']==(1 if mode else 2) and page['omitted_older']==2, page
  text=run(*mode,query)
  assert text.rstrip().endswith('2 older matches omitted (--all-time)'), text
  page=json.loads(run('--json',*mode,query,'--all-time'))
  assert page['total']==(2 if mode else 4) and page.get('omitted_older',0)==0, page
  text=run('--all-time',*mode,query)
  assert 'older matches omitted' not in text and 'old match' in text, text
for query in ['"qw"','qword']:
 page=json.loads(run('--json',query))
 assert page['total']==4 and page.get('omitted_older',0)==0, page
page=json.loads(run('--json','qw','-recent'))
assert page['total']==0 and page['omitted_older']==2, page
assert run('qw','-recent').rstrip().endswith('2 older matches omitted (--all-time)')
for flags in [['--harness','claude'],['--project','absent']]:
 page=json.loads(run('--json',*flags,'qw'))
 assert page['total']==0 and page.get('omitted_older',0)==0, page
page=json.loads(run('--json','--limit','1','qw'))
assert page['shown']==1 and page['omitted_older']==2, page
next_page=json.loads(run('--json','--limit','1','--cursor',page['next_cursor'],'qw'))
assert next_page['shown']==1 and next_page['omitted_older']==2, next_page
mismatch=subprocess.run([binary,'--json','--limit','1','--cursor',page['next_cursor'],'--all-time','qw'],env=env,text=True,capture_output=True)
assert mismatch.returncode!=0 and 'cursor' in mismatch.stderr, mismatch
assert '--all-time' in run('--help') and 'omitted_older' in run('--help')
print('text/JSON hits and sessions, inclusive 7-day boundary, --all-time, filters, and cursors checked')
PY
then record 'Short-prefix omitted footer and --all-time' PASS 0 "$(<"$TMP/short-prefix.txt")"; else record 'Short-prefix omitted footer and --all-time' FAIL 0 "$(<"$TMP/short-prefix.err")"; fi

# One transcript deliberately puts matching user/asst messages before a short tool row.
python3 - "$H" <<'PY'
import json,pathlib,sys
h=pathlib.Path(sys.argv[1]); p=h/'.claude/projects/-work-demo/55555555-5555-4555-8555-555555555555.jsonl'
sid='55555555-5555-4555-8555-555555555555'; filler=' '.join(['conversation']*70)
rows=[
 {'type':'user','uuid':'55555555-5555-4555-8555-555555555551','timestamp':'2026-09-27T11:00:00Z','cwd':str(h/'work/demo'),'sessionId':sid,'message':{'role':'user','content':'rankprobe '+filler}},
 {'type':'assistant','uuid':'55555555-5555-4555-8555-555555555552','timestamp':'2026-09-27T11:00:03Z','cwd':str(h/'work/demo'),'sessionId':sid,'message':{'role':'assistant','content':[{'type':'text','text':'rankprobe '+filler},{'type':'tool_use','id':'tool-rank-1','name':'Bash','input':{'command':'rankprobe'}}]}},
 {'type':'user','uuid':'55555555-5555-4555-8555-555555555553','timestamp':'2026-09-27T11:00:04Z','cwd':str(h/'work/demo'),'sessionId':sid,'message':{'role':'user','content':[{'type':'tool_result','tool_use_id':'tool-rank-1','content':'toolprobeonly output from helper'}]}}
]
p.write_text('\n'.join(json.dumps(x) for x in rows)+'\n')
PY
start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; if ((rc==0)) && grep -q '4 files, 1 changed' <<<"$out"; then record 'Tool-order fixture indexed' PASS $((SECONDS-start)) "$out"; else record 'Tool-order fixture indexed' FAIL $((SECONDS-start)) "$out"; fi
ranked=$("$BIN" --json rankprobe 2>&1); printf '%s\n' "$ranked" > "$SCREENS/tool-order.jsonl"
if python3 - "$SCREENS/tool-order.jsonl" <<'PY' > "$TMP/tool-order.txt" 2> "$TMP/tool-order.err"
import json,sys
rows=json.load(open(sys.argv[1]))['hits']; roles=[r['role'] for r in rows]
conversation=[i for i,r in enumerate(roles) if r in ('user','asst')]; tools=[i for i,r in enumerate(roles) if r=='tool']
assert conversation and tools, f'expected user/asst and tool hits, got {roles}'
assert max(conversation)<min(tools), f'tool row ranked before conversation hits: {roles}'
print(f'roles={roles}')
PY
then record 'Conversation hits precede matching tool row in JSON order' PASS 0 "$(<"$TMP/tool-order.txt")"; else record 'Conversation hits precede matching tool row in JSON order' FAIL 0 "$(<"$TMP/tool-order.err")"; fi
tool_only=$("$BIN" --json toolprobeonly 2>&1); if jq -e 'any(.hits[]; .role=="tool" and (.snippet|contains("toolprobeonly")))' <<<"$tool_only" >/dev/null; then record 'Tool-only match remains searchable' PASS 0 ''; else record 'Tool-only match remains searchable' FAIL 0 "$tool_only"; fi

# Dedicated 23-hit session for stateless pages and show/context behavior.
python3 - "$H" <<'PY'
import json,pathlib,sys
h=pathlib.Path(sys.argv[1]); p=h/'.claude/projects/-work-demo/66666666-6666-4666-8666-666666666666.jsonl'; sid='66666666-6666-4666-8666-666666666666'; rows=[]
for i in range(23):
 text=f'pageprobe PAGE_HIT_{i:02d} '+('LongText '+('boundary '*120) if i==10 else 'short context')
 role='user' if i%2==0 else 'assistant'
 rows.append({'type':role,'uuid':f'66666666-6666-4666-8666-{i:012d}','timestamp':f'2026-09-28T12:{i:02d}:00Z','cwd':str(h/'work/demo'),'sessionId':sid,'message':{'role':role,'content':text if role=='user' else [{'type':'text','text':text}]}})
p.write_text('\n'.join(json.dumps(x) for x in rows)+'\n')
PY
start=$SECONDS; out=$("$BIN" index 2>&1); rc=$?; if ((rc==0)) && grep -q '5 files, 1 changed' <<<"$out"; then record 'Pagination/show fixture indexed' PASS $((SECONDS-start)) "$out"; else record 'Pagination/show fixture indexed' FAIL $((SECONDS-start)) "$out"; fi
full_page=$("$BIN" --json --limit 500 pageprobe 2>&1); printf '%s\n' "$full_page" > "$TMP/page-full.json"
: > "$TMP/page-refs.txt"; page=$("$BIN" --json --limit 5 pageprobe 2>&1); page_count=0; cursor=''
while [[ -n $page ]]; do
  printf '%s\n' "$page" | jq -r '.hits[].ref' >> "$TMP/page-refs.txt" || break
  cursor=$(printf '%s\n' "$page" | jq -r '.next_cursor // empty'); page_count=$((page_count+1))
  [[ -z $cursor || $page_count -ge 20 ]] && break
  page=$("$BIN" --json --limit 5 --cursor "$cursor" pageprobe 2>&1)
done
python3 - "$TMP/page-full.json" "$TMP/page-refs.txt" <<'PY' > "$TMP/page-check.txt" 2> "$TMP/page-error.txt"
import json,sys
full=json.load(open(sys.argv[1])); expected=[x['ref'] for x in full['hits']]; actual=[x.strip() for x in open(sys.argv[2]) if x.strip()]
assert full['total']==23 and len(expected)==23, f'full page expected 23 hits, got total={full["total"]} shown={len(expected)}'
assert len(actual)==len(set(actual)), 'cursor pages contain duplicate refs'
assert actual==expected, f'cursor union skipped/reordered refs: {len(actual)} vs {len(expected)}'
print(f'{len(actual)} unique refs across cursor pages; union equals --limit 500')
PY
if [[ -s "$TMP/page-check.txt" ]]; then record 'Cursor pages cover every hit exactly once' PASS "$page_count" "$(<"$TMP/page-check.txt")"; else record 'Cursor pages cover every hit exactly once' FAIL "$page_count" "$(<"$TMP/page-error.txt")"; fi

# Default compact page is ten; the cursor footer/JSON field exist iff more remain.
text_first=$("$BIN" pageprobe 2>&1); json_first=$("$BIN" --json pageprobe 2>&1)
text_cursor=$(sed -n 's/^cursor: //p' <<<"$text_first"); json_cursor=$(jq -r '.next_cursor // empty' <<<"$json_first")
start=$SECONDS; text_second=$("$BIN" --cursor "$text_cursor" pageprobe 2>&1); text_cursor2=$(sed -n 's/^cursor: //p' <<<"$text_second"); text_last=$("$BIN" --cursor "$text_cursor2" pageprobe 2>&1)
json_second=$("$BIN" --json --cursor "$json_cursor" pageprobe 2>&1); json_cursor2=$(jq -r '.next_cursor // empty' <<<"$json_second"); json_last=$("$BIN" --json --cursor "$json_cursor2" pageprobe 2>&1)
if grep -q '^10/23 hits' <<<"$text_first" && [[ $(grep -Ec '^[[:xdigit:]]{12}:[0-9]+  ' <<<"$text_first") == 10 ]] && [[ -n $text_cursor && -n $json_cursor ]] && jq -e '.shown==10 and .total==23' <<<"$json_first" >/dev/null && grep -q '^10/23 hits' <<<"$text_second" && [[ -n $text_cursor2 && -n $json_cursor2 ]] && grep -q '^3/23 hits' <<<"$text_last" && ! grep -q '^cursor:' <<<"$text_last" && jq -e '.shown==3 and .total==23 and (has("next_cursor")|not)' <<<"$json_last" >/dev/null; then record 'Default page size and cursor footer/JSON parity' PASS $((SECONDS-start)) '10 + 10 + 3 rows; text and JSON cursors appear only while more remain'; else record 'Default page size and cursor footer/JSON parity' FAIL $((SECONDS-start)) "first=$text_first last=$text_last json_last=$json_last"; fi
bad_query=$("$BIN" --json --cursor "$json_cursor" snapshot 2>&1); bad_query_rc=$?
bad_flags=$("$BIN" --json --limit 5 --cursor "$json_cursor" pageprobe 2>&1); bad_flags_rc=$?
if ((bad_query_rc!=0 && bad_flags_rc!=0)) && grep -q 'cursor does not match this query or flags' <<<"$bad_query" && grep -q 'cursor does not match this query or flags' <<<"$bad_flags"; then record 'Cursor rejects changed query and flags clearly' PASS 0 ''; else record 'Cursor rejects changed query and flags clearly' FAIL 0 "query=$bad_query flags=$bad_flags"; fi

# Grouped session totals/hit counts agree with message-level results and top session.
hits_snapshot=$("$BIN" --json snapshot 2>&1); sessions_snapshot=$("$BIN" --json --sessions snapshot 2>&1)
printf '%s\n' "$hits_snapshot" > "$TMP/snapshot-hits.json"; printf '%s\n' "$sessions_snapshot" > "$TMP/snapshot-sessions.json"
python3 - "$TMP/snapshot-hits.json" "$TMP/snapshot-sessions.json" <<'PY' > "$TMP/sessions-check.txt" 2> "$TMP/sessions-error.txt"
import json,sys
h=json.load(open(sys.argv[1])); s=json.load(open(sys.argv[2]))
assert s['total']==h['total_sessions'] and sum(x['hits'] for x in s['sessions'])==h['total'], f'hit/session totals disagree: {h["total"]}/{h["total_sessions"]} vs {s["total"]}/{sum(x["hits"] for x in s["sessions"])}'
assert s['sessions'] and h['hits'][0]['ref'].split(':',1)[0]==s['sessions'][0]['ref'], 'sessions are not ranked by their best hit'
print(f'{h["total"]} hits across {h["total_sessions"]} sessions; counts sum and best-hit rank agrees')
PY
if [[ -s "$TMP/sessions-check.txt" ]]; then record '--sessions ranking/counts agree with hit list' PASS 0 "$(<"$TMP/sessions-check.txt")"; else record '--sessions ranking/counts agree with hit list' FAIL 0 "$(<"$TMP/sessions-error.txt")"; fi

# show ref exposes context, resume metadata, hit marker, truncation, and --all cursor pages.
show_ref=$(jq -r '.hits[] | select(.ref|endswith(":10")) | .ref' "$TMP/page-full.json")
show_json=$("$BIN" show "$show_ref" --context 2 --json 2>&1); printf '%s\n' "$show_json" > "$TMP/show-context.json"
show_text=$("$BIN" show "$show_ref" --context 2 2>&1)
python3 - "$TMP/show-context.json" <<'PY' > "$TMP/show-check.txt" 2> "$TMP/show-error.txt"
import json,sys
p=json.load(open(sys.argv[1])); selected=[m for m in p['messages'] if m['hit']]
assert p['shown']==5 and p['total']==5 and len(selected)==1, f'expected selected hit and 2 context messages each side, got {p["shown"]}/{p["total"]}'
assert 'PAGE_HIT_08' in p['messages'][0]['text'] and 'PAGE_HIT_12' in p['messages'][-1]['text'], 'context bounds incorrect'
assert p['resume_cmd']=='claude --resume 66666666-6666-4666-8666-666666666666', p['resume_cmd']
assert p['project']=='demo' and p['cwd'].endswith('/work/demo'), f'missing project/cwd: {p["project"]} {p["cwd"]}'
assert len(selected[0]['text'])<=400 and selected[0]['text'].endswith('…'), 'long selected text was not truncated'
print('5-message context, selected hit, resume command, project/cwd, and 400-cell truncation verified')
PY
if [[ -s "$TMP/show-check.txt" ]] && grep -Eq '^> [0-9]{2}:[0-9]{2} user:' <<<"$show_text" && grep -q 'resume: claude --resume 66666666-6666-4666-8666-666666666666' <<<"$show_text"; then record 'show ref context and text hit marker' PASS 0 "$(<"$TMP/show-check.txt")"; else record 'show ref context and text hit marker' FAIL 0 "$(<"$TMP/show-error.txt") $show_text"; fi
show_all=$("$BIN" show "$show_ref" --all --json 2>&1); printf '%s\n' "$show_all" > "$TMP/show-all-first.json"; : > "$TMP/show-all-markers.txt"; show_pages=0
while [[ -n $show_all ]]; do
 printf '%s\n' "$show_all" | jq -r '.messages[].text' | grep -oE 'PAGE_HIT_[0-9]{2}' >> "$TMP/show-all-markers.txt" || :
 show_cursor=$(printf '%s\n' "$show_all" | jq -r '.next_cursor // empty'); show_pages=$((show_pages+1)); [[ -z $show_cursor || $show_pages -ge 10 ]] && break
 show_all=$("$BIN" show "$show_ref" --all --json --cursor "$show_cursor" 2>&1)
done
if python3 - "$TMP/show-all-markers.txt" <<'PY' > "$TMP/show-all-check.txt" 2> "$TMP/show-all-error.txt"
import sys
found=[x.strip() for x in open(sys.argv[1]) if x.strip()]; expected=[f'PAGE_HIT_{i:02}' for i in range(23)]
assert len(found)==23 and len(set(found))==23 and set(found)==set(expected), f'--all pages skipped/duplicated messages: {len(found)} unique={len(set(found))}'
print('all 23 messages returned once across show --all pages')
PY
then record 'show --all paginates the whole session' PASS "$show_pages" "$(<"$TMP/show-all-check.txt")"; else record 'show --all paginates the whole session' FAIL "$show_pages" "$(<"$TMP/show-all-error.txt")"; fi

# --help is immediate and must not create/open the index or run a search.
export KIOKU_INDEX="$H/index/help-must-not-exist.db"; rm -f "$KIOKU_INDEX"
help_out=$("$BIN" --help 2>&1); help_rc=$?
if ((help_rc==0)) && grep -q '^Usage:' <<<"$help_out" && grep -q 'kioku show <ref|session-id>' <<<"$help_out" && [[ ! -e $KIOKU_INDEX ]]; then record 'kioku --help exits with usage before search/index' PASS 0 ''; else record 'kioku --help exits with usage before search/index' FAIL 0 "$help_out index_exists=$([[ -e $KIOKU_INDEX ]] && echo yes || echo no)"; fi
export KIOKU_INDEX="$H/index/index.db"

# Query correctness cases from SPEC's Expected behavior plus languages/filters.
check_query(){ local q=$1 mode=$2 want=${3:-}; local t=$SECONDS out rc; out=$("$BIN" --json "$q" 2>&1); rc=$?; local ok=1
 if ((rc)); then ok=0; elif [[ $mode == empty ]]; then jq -e '.total==0 and .shown==0 and (.hits|length)==0' <<<"$out" >/dev/null 2>&1 || ok=0; elif ! grep -Fq "$want" <<<"$out"; then ok=0; fi
 if ((ok)); then record "query: $q ($mode)" PASS $((SECONDS-t)) ''; else record "query: $q ($mode)" FAIL $((SECONDS-t)) "expected $mode $want; got: $out"; failbug "Query $q" "HOME=$HOME KIOKU_INDEX=$KIOKU_INDEX ./kioku --json '$q'" "${mode} ${want}" "$out"; fi
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
start=$SECONDS; recent=$("$BIN" --json 2>&1); rc=$?; if ((rc==0)) && jq -e '.shown>0 and (.hits|length)==.shown and all(.hits[]; has("ref") and has("harness") and has("snippet"))' <<<"$recent" >/dev/null 2>&1; then record 'Empty query lists recent messages as compact JSON' PASS $((SECONDS-start)) "$(jq -r '.shown' <<<"$recent") rows"; else record 'Empty query lists recent messages as compact JSON' FAIL $((SECONDS-start)) "$recent"; fi
start=$SECONDS; malformed=$("$BIN" --json '"' 2>&1); rc=$?; if ((rc==0)) && jq -e '.total==0 and (.hits|length)==0' <<<"$malformed" >/dev/null 2>&1; then record 'Malformed quote query does not crash' PASS $((SECONDS-start)) ''; else record 'Malformed quote query does not crash' FAIL $((SECONDS-start)) "$malformed"; fi

start=$SECONDS; out=$("$BIN" --json snapshot 2>&1); rc=$?; printf '%s\n' "$out" > "$SCREENS/json-snapshot.jsonl"
if ((rc==0)) && jq -e 'has("shown") and has("total") and has("total_sessions") and (.hits|length)==.shown and all(.hits[]; ([keys[]]|sort)==(["ref","harness","project","age","role","snippet"]|sort))' <<<"$out" >/dev/null; then record 'Compact JSON search-page schema' PASS $((SECONDS-start)) "$(jq -r '.shown' <<<"$out") hits"; else record 'Compact JSON search-page schema' FAIL $((SECONDS-start)) "$out"; fi
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
export KIOKU_INDEX="$H/index/tui.db"
tmux new-session -d -x 120 -y 40 -s "he2e-$$" "cd '$ROOT' && HOME='$HOME' KIOKU_INDEX='$KIOKU_INDEX' KIOKU_THEME=light TERM=xterm-256color exec ./kioku snapshot" 2>/dev/null
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
if [[ $state == 1 ]] && ! grep -q 'kioku ▸' "$SCREENS/tui-after-ctrl-c.txt"; then record 'Ctrl-C exits and restores terminal (process + alternate screen)' PASS 0 ''; else record 'Ctrl-C exits and restores terminal (process exits)' FAIL 0 "pane_dead=$state"; fi

# Stub agents and editor: assert exec argv/cwd and detached editor arguments.
STUB="$TMP/stub"; mkdir -p "$STUB"; export STUBLOG="$TMP/stub.log"
for tool in claude codex pi zed; do cat > "$STUB/$tool" <<'SH'
#!/bin/sh
printf '%s|%s|%s\n' "$(basename "$0")" "$PWD" "$*" >> "$STUBLOG"
SH
chmod +x "$STUB/$tool"; done
export PATH="$STUB:$PATH"
# Resume Claude: execute stub in real synthetic cwd after selecting the first hit.
export KIOKU_INDEX="$H/index/resume.db"
tmux new-session -d -x 100 -y 32 -s "hrsm-$$" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' KIOKU_INDEX='$KIOKU_INDEX' TERM=xterm-256color exec ./kioku --harness claude snapshot" 2>/dev/null
sleep 1; tmux send-keys -t "hrsm-$$" Escape; sleep .2; tmux send-keys -t "hrsm-$$" Enter; sleep .8
CWD_PHYS=$(cd "$H/work/demo" && pwd -P)
if grep -Fq "claude|$CWD_PHYS|--resume 11111111-1111-4111-8111-111111111111" "$STUBLOG" 2>/dev/null; then record 'Resume Claude stub argv + cwd' PASS 0 "$(tail -1 "$STUBLOG")"; else record 'Resume Claude stub argv + cwd' FAIL 0 "$(cat "$STUBLOG" 2>/dev/null || echo no stub call)"; fi
# Codex and Pi use their harness-specific resume forms too.
for harness in codex pi; do
  session="hrsm-$harness-$$"; export KIOKU_INDEX="$H/index/resume-$harness.db"
  tmux new-session -d -x 100 -y 32 -s "$session" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' KIOKU_INDEX='$KIOKU_INDEX' TERM=xterm-256color exec ./kioku --harness $harness snapshot" 2>/dev/null
  sleep 1; tmux send-keys -t "$session" Escape; sleep .2; tmux send-keys -t "$session" Enter; sleep .6
  if [[ $harness == codex ]]; then expected="codex|$CWD_PHYS|resume 22222222-2222-4222-8222-222222222222"; else pi_path=$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$H/.pi/agent/sessions/-work-demo/33333333-3333-4333-8333-333333333333.jsonl"); expected="pi|$CWD_PHYS|--session $pi_path"; fi
  if grep -Fq "$expected" "$STUBLOG" 2>/dev/null; then record "Resume $harness stub argv + cwd" PASS 0 "$expected"; else record "Resume $harness stub argv + cwd" FAIL 0 "expected $expected; log: $(cat "$STUBLOG" 2>/dev/null)"; fi
done
# Editor configuration takes precedence and receives project cwd while TUI survives.
export KIOKU_INDEX="$H/index/editor.db" KIOKU_EDITOR="$STUB/zed"
tmux new-session -d -x 100 -y 32 -s "hedt-$$" "cd '$ROOT' && HOME='$HOME' PATH='$PATH' STUBLOG='$STUBLOG' KIOKU_EDITOR='$KIOKU_EDITOR' KIOKU_INDEX='$KIOKU_INDEX' TERM=xterm-256color exec ./kioku snapshot" 2>/dev/null
sleep 1; tmux send-keys -t "hedt-$$" Escape; sleep .2; tmux send-keys -t "hedt-$$" o; sleep .5
if grep -Fq 'zed|' "$STUBLOG" 2>/dev/null && grep -Fq 'work/demo' "$STUBLOG" 2>/dev/null; then record 'Editor stub launch + project directory' PASS 0 "$(tail -1 "$STUBLOG")"; else record 'Editor stub launch + project directory' FAIL 0 "zed not launched with project directory; log=$(cat "$STUBLOG" 2>/dev/null)"; fi
tmux capture-pane -t "hedt-$$" -p > "$SCREENS/tui-editor.txt" 2>&1
if tmux has-session -t "hedt-$$" 2>/dev/null; then record 'Editor launch leaves TUI alive' PASS 0 ''; else record 'Editor launch leaves TUI alive' FAIL 0 'TUI exited'; fi

tmux kill-session -t "hedt-$$" 2>/dev/null || :
# n/N must still navigate to matching tool-output messages in the transcript.
export KIOKU_INDEX="$H/index/tool-nav.db"
tmux new-session -d -x 120 -y 40 -s "htool-$$" "cd '$ROOT' && HOME='$HOME' KIOKU_INDEX='$KIOKU_INDEX' KIOKU_THEME=light TERM=xterm-256color exec ./kioku toolprobeonly" 2>/dev/null
sleep 1; tmux send-keys -t "htool-$$" Escape; sleep .2; tmux send-keys -t "htool-$$" n; sleep .2; tmux capture-pane -t "htool-$$" -p > "$SCREENS/tui-tool-nav-next.txt"
tmux send-keys -t "htool-$$" N; sleep .2; tmux capture-pane -t "htool-$$" -p > "$SCREENS/tui-tool-nav-prev.txt"
if grep -Eq '[✱›].*tool.*toolprobeonly' "$SCREENS/tui-tool-nav-next.txt" && grep -Eq '[✱›].*tool.*toolprobeonly' "$SCREENS/tui-tool-nav-prev.txt"; then record 'TUI n/N visits matching tool hit' PASS 0 'both directions retain the tool hit in transcript'; else record 'TUI n/N visits matching tool hit' FAIL 0 "n=$(grep -E 'toolprobeonly' "$SCREENS/tui-tool-nav-next.txt") N=$(grep -E 'toolprobeonly' "$SCREENS/tui-tool-nav-prev.txt")"; fi
tmux kill-session -t "htool-$$" 2>/dev/null || :
# Truncation test has a hit crossing a Latin word at the snippet's right boundary.
export KIOKU_INDEX="$H/index/trunc.db"
tmux new-session -d -x 120 -y 40 -s "htrunc-$$" "cd '$ROOT' && HOME='$HOME' KIOKU_INDEX='$KIOKU_INDEX' KIOKU_THEME=light TERM=xterm-256color exec ./kioku cutprobe" 2>/dev/null
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
python3 - <<'PY'
import json,os,pathlib
root=pathlib.Path(os.environ['PERF'])
claude=root/'.claude/projects/newest-first/000-new.jsonl'; claude.parent.mkdir(parents=True)
rows=[{'type':'user','uuid':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','timestamp':'2026-10-01T10:00:00Z','cwd':'/work/new','sessionId':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','message':{'role':'user','content':'synthetic newest session'}},{'type':'assistant','uuid':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','timestamp':'2026-10-01T10:00:01Z','cwd':'/work/new','sessionId':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','message':{'role':'assistant','content':[{'type':'text','text':'synthetic NEWEST_MATCH_MARKER'}]}}]
claude.write_text('\n'.join(json.dumps(x) for x in rows)+'\n')
pi=root/'.pi/agent/sessions/zz-old/999-old.jsonl'; pi.parent.mkdir(parents=True)
rows=[{'type':'session','version':3,'id':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','timestamp':'2025-01-01T00:00:00Z','cwd':'/work/old'},{'type':'message','id':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','timestamp':'2025-01-01T00:00:01Z','message':{'role':'user','content':[{'type':'text','text':'synthetic OLDEST_MATCH_MARKER'}]}}]
pi.write_text('\n'.join(json.dumps(x) for x in rows)+'\n')
PY
export HOME="$PERF" KIOKU_INDEX="$TMP/perf.db"
python3 - "$BIN" "$TMP/perf-metrics.json" <<'PY'
import json,math,os,statistics,subprocess,sys,time
binary,outfile=sys.argv[1:]; env=os.environ.copy(); env['KIOKU_DEBUG_TIMING']='1'
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

# Very common term: newest session file is indexed first, oldest matching file last.
start=$SECONDS; semantic=$("$BIN" --json synthetic 2>&1); semantic_rc=$?; printf '%s\n' "$semantic" > "$SCREENS/common-word.jsonl"
if ((semantic_rc==0)) && python3 - "$SCREENS/common-word.jsonl" > "$TMP/semantic-summary.txt" 2> "$TMP/semantic-error.txt" <<'PY'
import json,sys
page=json.load(open(sys.argv[1])); rows=page['hits']; harnesses={r['harness'] for r in rows}
assert 'claude' in harnesses and 'codex' in harnesses, f'only harnesses in common-word results: {sorted(harnesses)}'
assert rows and rows[0]['harness']=='claude' and 'NEWEST_MATCH_MARKER' in rows[0]['snippet'], 'newest Claude match was absent or misranked at the top'
print(f'{len(rows)} rows; harnesses={sorted(harnesses)}; newest={rows[0]["snippet"]}')
PY
then record 'Search semantics: common term is ranked by message time, not insertion order' PASS $((SECONDS-start)) "$(<"$TMP/semantic-summary.txt")"; else record 'Search semantics: common term is ranked by message time, not insertion order' FAIL $((SECONDS-start)) "exit=$semantic_rc error=$(<"$TMP/semantic-error.txt") output=$(tail -3 "$SCREENS/common-word.jsonl")"; fi

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
start=$SECONDS; appended=$(KIOKU_DEBUG_TIMING=1 "$BIN" --json appendtoken 2>"$TMP/append-timing.txt"); append_rc=$?; append_ms=$(sed -nE 's/^timing sync_changes=([0-9.]+)ms$/\1/p' "$TMP/append-timing.txt"); after_append=$("$BIN" index 2>&1)
if ((append_rc==0)) && grep -q appendtoken <<<"$appended" && grep -q 'codex: 200001 messages' <<<"$after_append" && grep -q '0 changed' <<<"$after_append" && [[ -n $append_ms ]] && awk -v x="$append_ms" 'BEGIN{exit !(x<200)}'; then record 'Append sync: next CLI query finds new line; only tail parsed' PASS $((SECONDS-start)) "sync_changes=${append_ms}ms; $after_append"; else record 'Append sync: next CLI query finds new line; only tail parsed' FAIL $((SECONDS-start)) "query=$appended timing=$(cat "$TMP/append-timing.txt") index=$after_append"; fi
partial=$(KIOKU_DEBUG_TIMING=1 "$BIN" --json partialtoken 2>"$TMP/partial-timing.txt"); partial_rc=$?; if ((partial_rc==0)) && jq -e '.total==0 and (.hits|length)==0' <<<"$partial" >/dev/null 2>&1; then record 'Partial final line is withheld until newline' PASS 0 "$(cat "$TMP/partial-timing.txt")"; else record 'Partial final line is withheld until newline' FAIL 0 "unexpected query output: $partial"; fi
cat "$TMP/partial-rest" >> "$append_file"; completed=$("$BIN" --json partialtoken 2>&1); complete_index=$("$BIN" index 2>&1)
if grep -q partialtoken <<<"$completed" && grep -q 'codex: 200002 messages' <<<"$complete_index" && grep -q '0 changed' <<<"$complete_index"; then record 'Partial line is re-read and indexed when completed' PASS 0 "$complete_index"; else record 'Partial line is re-read and indexed when completed' FAIL 0 "query=$completed index=$complete_index"; fi

# Independent read-only real-store count versus app indexing with an isolated DB.
if [[ ${KIOKU_E2E_REAL:-0} == 1 ]]; then
REALHOME="$REALHOME_DEFAULT"; REALTMP="$TMP/real"; mkdir -p "$REALTMP" "$TEST/out"; export REALHOME REALTMP
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
export HOME="$REALHOME" KIOKU_INDEX="$REALTMP/index.db"
start=$SECONDS; realout=$("$BIN" index --rebuild 2>&1); rc=$?; python3 - "$REALTMP/independent.txt" "$REALTMP/app.txt" <<'PY'
import sqlite3,sys
rows=sqlite3.connect(sys.argv[2].replace('app.txt','index.db')).execute('select harness,count(distinct uid),sum((select count(*) from messages m where m.session_uid=s.uid)) from sessions s group by harness').fetchall()
open(sys.argv[2],'w').write('\n'.join('%s %s %s'%r for r in rows)+'\n')
PY
{ printf 'independent: harness total_jsonl raw_user_assistant_text_blocks\n'; cat "$REALTMP/independent.txt"; printf 'indexed: harness sessions message_rows\n'; cat "$REALTMP/app.txt"; } > "$TEST/out/real-store-counts.txt"
# Raw user/assistant text blocks are a conservative lower bound: indexed rows also include tools.
if ((rc==0)) && python3 - "$REALTMP/independent.txt" "$REALTMP/app.txt" <<'PY'
import sys
ind={x.split()[0]:int(x.split()[2]) for x in open(sys.argv[1])}; app={x.split()[0]:int(x.split()[2]) for x in open(sys.argv[2])}
for h,n in ind.items():
 a=app.get(h,0)
 if n and a<n: print(f'{h}: indexed={a} below independent user/assistant lines={n}'); sys.exit(1)
 if n and not a: print(f'{h}: independent={n}, indexed=0'); sys.exit(1)
PY
then record 'Real stores: read-only independent lower-bound sanity' PASS $((SECONDS-start)) "$(tr '\n' ';' < "$TEST/out/real-store-counts.txt"); lower-bound only: indexed counts include tool rows and split content blocks"; else record 'Real stores: read-only independent lower-bound sanity' FAIL $((SECONDS-start)) "$realout; $(tr '\n' ';' < "$TEST/out/real-store-counts.txt")"; failbug 'Real store message undercount' 'KIOKU_INDEX=<temp>/index.db ./kioku index --rebuild; compare to test/out/real-store-counts.txt' 'indexed rows >= independent user/assistant text blocks' "$realout; see test/out/real-store-counts.txt"; fi
else
  skip 'Real stores: read-only independent lower-bound sanity' 'Set KIOKU_E2E_REAL=1 to opt in to reading this machine’s ~/.claude, ~/.codex, and ~/.pi stores.'
fi

printf '\n**Summary:** %d PASS, %d FAIL.\n' "$PASS" "$FAIL" >> "$REPORT"
# Committed artifacts must not carry machine-specific paths (e.g. macOS /var/folders temp dirs).
redact_root=$(cd "$TMP" && pwd -P)
for f in "$REPORT" "$TEST/BUGS.md" "$SCREENS"/*; do
  [[ -f $f ]] || continue
  sed -i '' -e "s#${redact_root}#<fixture>#g" -e "s#${TMP}#<fixture>#g" -e "s#/private/var/folders/[^ |\"']*/T/kioku-e2e\.[A-Za-z0-9]*#<fixture>#g" -e "s#/var/folders/[^ |\"']*/T/kioku-e2e\.[A-Za-z0-9]*#<fixture>#g" -e "s#${ROOT}#<repo>#g" -E -e "s#(/private)?/var/folders/[^ |\"']*#<fixture>#g" "$f"
done
printf '%d PASS / %d FAIL — report: test/e2e-report.md\n' "$PASS" "$FAIL"
((FAIL==0))
