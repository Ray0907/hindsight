#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [new-synthetic-HOME]" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  home=$1
  if [ -e "$home" ]; then
    echo "refusing to overwrite existing path: $home" >&2
    exit 1
  fi
  mkdir -p "$home"
else
  home=$(mktemp -d "${TMPDIR:-/tmp}/kioku-fixture.XXXXXX")
fi

# All paths and transcript text below are synthetic; this script never reads the real HOME.
claude="$home/.claude/projects/-work-demo"
codex="$home/.codex/sessions/2026/09/27"
pi="$home/.pi/agent/sessions/-work-demo"
mkdir -p "$claude" "$codex" "$pi"

cat > "$claude/11111111-1111-4111-8111-111111111111.jsonl" <<'JSONL'
{"parentUuid":null,"isSidechain":false,"promptId":"fixture-prompt-1","type":"user","message":{"role":"user","content":"Find the snapshot and resume path; resuming should preserve JSON output."},"uuid":"11111111-1111-4111-8111-111111111101","timestamp":"2026-09-27T10:00:00.000Z","cwd":"/work/demo","sessionId":"11111111-1111-4111-8111-111111111111","version":"1.0.0"}
{"parentUuid":"11111111-1111-4111-8111-111111111101","isSidechain":false,"type":"assistant","message":{"model":"fixture-model","role":"assistant","content":[{"type":"text","text":"SNAPSHOT: json_extract handles low-water marks, S3 uploads, cjk.c, and naïve input."}]},"uuid":"11111111-1111-4111-8111-111111111102","timestamp":"2026-09-27T10:00:03.000Z","session_id":"11111111-1111-4111-8111-111111111111","cwd":"/work/demo","sessionId":"11111111-1111-4111-8111-111111111111"}
{"parentUuid":"11111111-1111-4111-8111-111111111102","isSidechain":false,"type":"user","message":{"role":"user","content":"紅茶: 日月潭紅茶產於南投縣魚池鄉。魚池と紅茶を探す。한국어 검색도 확인합니다."},"uuid":"11111111-1111-4111-8111-111111111103","timestamp":"2026-09-27T10:01:00.000Z","cwd":"/work/demo","sessionId":"11111111-1111-4111-8111-111111111111"}
{"parentUuid":"11111111-1111-4111-8111-111111111103","isSidechain":false,"type":"assistant","message":{"model":"fixture-model","role":"assistant","content":[{"type":"text","text":"茶 is searchable; 日本語の議事録と 한국어 세션도 이 fixture에 있습니다."}]},"uuid":"11111111-1111-4111-8111-111111111104","timestamp":"2026-09-27T10:01:05.000Z","cwd":"/work/demo","sessionId":"11111111-1111-4111-8111-111111111111"}
{"broken-json":
{"parentUuid":"11111111-1111-4111-8111-111111111104","isSidechain":false,"type":"user","message":{"role":"user","content":"Parser continues after malformed line: recoverytoken."},"uuid":"11111111-1111-4111-8111-111111111105","timestamp":"2026-09-27T10:02:00.000Z","cwd":"/work/demo","sessionId":"11111111-1111-4111-8111-111111111111"}
JSONL

cat > "$codex/rollout-2026-09-27T10-05-00-019d0000-0000-7000-8000-000000000002.jsonl" <<'JSONL'
{"timestamp":"2026-09-27T10:05:00.000Z","type":"session_meta","payload":{"id":"22222222-2222-4222-8222-222222222222","timestamp":"2026-09-27T10:05:00.000Z","cwd":"/work/demo","originator":"codex","cli_version":"fixture","source":"cli","model_provider":"fixture"}}
{"timestamp":"2026-09-27T10:05:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Search for snapshot, resum, json_extract, low-water, S3, and cjk.c."}]}}
{"timestamp":"2026-09-27T10:05:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"SNAPSHOT is ready; resuming is safe, but a shorter prefix is not a match. The phrase is black tea."}]}}
{"timestamp":"2026-09-27T10:06:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"魚池 appears inside 日月潭紅茶產於南投縣魚池鄉. 日本語の検索と 한국어 검색."}]}}
{"timestamp":"2026-09-27T10:06:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"紅茶 is tea; single-character 茶 should match. naïve accents are searchable."}]}}
not-json
{"timestamp":"2026-09-27T10:07:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Parser continues after malformed line: recoverytoken."}]}}
JSONL

cat > "$pi/33333333-3333-4333-8333-333333333333.jsonl" <<'JSONL'
{"type":"session","version":3,"id":"33333333-3333-4333-8333-333333333333","timestamp":"2026-09-27T10:10:00.000Z","cwd":"/work/demo"}
{"type":"message","id":"33333333-3333-4333-8333-333333333301","parentId":null,"timestamp":"2026-09-27T10:10:02.000Z","message":{"role":"user","content":[{"type":"text","text":"Find SNAPSHOT and resuming; test S3, json_extract, low-water, and cjk.c."}],"timestamp":1790503802000}}
{"type":"message","id":"33333333-3333-4333-8333-333333333302","parentId":"33333333-3333-4333-8333-333333333301","timestamp":"2026-09-27T10:10:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"A snapshot can resume safely; the phrase is black tea, and naïve input is searchable."}],"timestamp":1790503805000,"provider":"fixture","model":"fixture-model","stopReason":"stop"}}
{"type":"message","id":"33333333-3333-4333-8333-333333333303","parentId":"33333333-3333-4333-8333-333333333302","timestamp":"2026-09-27T10:11:00.000Z","message":{"role":"user","content":[{"type":"text","text":"魚池 in 日月潭紅茶產於南投縣魚池鄉. 日本語の会話です。한국어 대화입니다."}],"timestamp":1790503860000}}
{"type":"message","id":"33333333-3333-4333-8333-333333333304","parentId":"33333333-3333-4333-8333-333333333303","timestamp":"2026-09-27T10:11:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"茶 is one character; 红茶 and 紅茶 are both represented."}],"timestamp":1790503863000,"provider":"fixture","model":"fixture-model","stopReason":"stop"}}
{"broken-json":
{"type":"message","id":"33333333-3333-4333-8333-333333333305","parentId":"33333333-3333-4333-8333-333333333304","timestamp":"2026-09-27T10:12:00.000Z","message":{"role":"user","content":[{"type":"text","text":"Parser continues after malformed line: recoverytoken."}],"timestamp":1790503920000}}
JSONL

# Separate synthetic HOME keeps Grok coverage independent of baseline counts.
grok="$home/grok-home/.grok/sessions/%2Fwork%2Fgrok%20fallback/55555555-5555-4555-8555-555555555555"
mkdir -p "$grok"
cat > "$grok/summary.json" <<'JSON'
{"info":{"id":"grok-native-id","cwd":"/work/grok demo"},"created_at":"2026-09-27T10:15:00Z","current_model_id":"grok-summary-model"}
JSON
cat > "$grok/chat_history.jsonl" <<'JSONL'
{"type":"user","content":"grokteatoken: 日月潭紅茶產於南投縣魚池鄉。日本語と 한국어 대화."}
{"type":"assistant","model_id":"grok-message-model","content":[{"type":"text","text":"grokanswer: checking the tea notes."}],"tool_calls":[{"id":"tea-call","name":"read_file","arguments":"{\"path\":\"groktea.txt\"}"}]}
{"type":"tool_result","tool_call_id":"tea-call","content":[{"type":"text","text":"groktearesult: notes found.\nSecond line is compacted."}]}
{"broken-json":
{"type":"user","content":[{"type":"text","text":"grokrecovery: continued after malformed line."}]}
{"type":"assistant","tool_calls":[{"id":"pending","name":"bash","input":{"command":"echo grokappend"}}]}
JSONL

# Separate synthetic HOME keeps self-lookup coverage independent of baseline counts.
python3 - "$home/self-lookups" <<'PY'
import json,pathlib,sys
home=pathlib.Path(sys.argv[1])
commands=['kioku --sessions secretword', ' TAG="two words" command kioku --json secretword', 'command TAG=yes kioku secretword']
for harness,store in [('claude','.claude/projects/self'),('codex','.codex/sessions'),('pi','.pi/agent/sessions/self')]:
 rows=[]
 def emit(role,text='',calls=(),call_id='',name='bash'):
  ts='2026-09-27T11:00:00Z'
  if harness=='claude':
   content=[{'type':'text','text':text}] if text else []
   content += [{'type':'tool_use','id':i,'name':n,'input':{'command':cmd}} for i,n,cmd in calls]
   if role=='tool': content=[{'type':'tool_result','tool_use_id':call_id,'content':text}]
   rows.append({'type':'user' if role in ('user','tool') else 'assistant','timestamp':ts,'cwd':'/work/self-lookups','sessionId':'self-claude','message':{'role':role,'content':content}})
  elif harness=='codex':
   if text and role!='tool': rows.append({'type':'response_item','timestamp':ts,'payload':{'type':'message','role':role,'content':[{'type':'input_text' if role=='user' else 'output_text','text':text}]}})
   for i,n,cmd in calls:
    payload={'type':'custom_tool_call','input':cmd} if i=='self-2' else {'type':'function_call','arguments':json.dumps({'cmd':cmd})}
    rows.append({'type':'response_item','timestamp':ts,'payload':dict(payload,call_id=i,name=n)})
   if role=='tool': rows.append({'type':'response_item','timestamp':ts,'payload':{'type':'custom_tool_call_output' if call_id=='self-2' else 'function_call_output','call_id':call_id,'output':text}})
  else:
   content=[{'type':'text','text':text}] if text else []
   content += [{'type':'toolCall','id':i,'name':n,'arguments':{'command':cmd}} for i,n,cmd in calls]
   rows.append({'type':'message','timestamp':ts,'message':{'role':'toolResult' if role=='tool' else role,'content':content,'toolCallId':call_id,'toolName':name}})
 if harness=='codex': rows.append({'type':'session_meta','payload':{'id':'self-codex','cwd':'/work/self-lookups'}})
 if harness=='pi': rows.append({'type':'session','id':'self-pi','cwd':'/work/self-lookups'})
 emit('assistant','Searching archive.',calls=[('self-0','bash',commands[0]),('ordinary','bash','echo ordinaryprobe')])
 emit('tool','ordinaryprobe output',call_id='ordinary')
 emit('tool','secretword lookup result',call_id='self-0')
 for i,cmd in enumerate(commands[1:],1):
  emit('assistant',calls=[(f'self-{i}','bash',cmd)])
  emit('tool','secretword lookup result',call_id='' if harness=='pi' else f'self-{i}')
 # Leave an unresolved call for the E2E to append its result after indexing.
 emit('assistant',calls=[('pending','bash','kioku pendingsecret')])
 path=home/store/'self.jsonl'; path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(''.join(json.dumps(r)+'\n' for r in rows))
normal=home/'.claude/projects/normal/normal.jsonl'; normal.parent.mkdir(parents=True,exist_ok=True)
rows=[{'type':role,'timestamp':'2026-09-27T11:01:00Z','cwd':'/work/normal','sessionId':'normal','message':{'role':role,'content':text}} for role,text in [('user','Please remember secretword.'),('assistant','kioku merely mentions secretword.')]]
rows[-1]['message']['content']=[{'type':'text','text':rows[-1]['message']['content']}]
for i,cmd in enumerate(['echo kioku mentionprobe','kioku-other mentionprobe','FOO=kioku echo mentionprobe']):
 rows.append({'type':'assistant','message':{'content':[{'type':'tool_use','id':str(i),'name':'bash','input':{'command':cmd}}]}})
 rows.append({'type':'user','message':{'content':[{'type':'tool_result','tool_use_id':str(i),'content':'mentionprobe result'}]}})
normal.write_text(''.join(json.dumps(r)+'\n' for r in rows))
PY

# Relocated copies exercise native config dirs, including spaces in paths.
mkdir -p "$home/relocated/claude config" "$home/relocated/codex config" "$home/relocated/pi config"
cp -R "$home/.claude/projects" "$home/relocated/claude config/projects"
cp -R "$home/.codex/sessions" "$home/relocated/codex config/sessions"
cp -R "$home/.pi/agent/sessions" "$home/relocated/pi config/sessions"

printf '%s\n' "$home"
