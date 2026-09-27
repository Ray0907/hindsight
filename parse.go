package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type message struct {
	ID    int64  `json:"-"`
	Index int    `json:"-"`
	TS    string `json:"ts"`
	Role  string `json:"role"`
	Text  string `json:"text"`
}
type session struct {
	UID, Harness, NativeID, Path, CWD, Project, Model, Started, Updated string
	Messages                                                            []message
}

func str(v any) string         { s, _ := v.(string); return s }
func obj(v any) map[string]any { m, _ := v.(map[string]any); return m }
func arr(v any) []any          { a, _ := v.([]any); return a }
func clean(s string) string    { return strings.TrimSpace(strings.ReplaceAll(s, "\x00", "")) }
func first(s string) string {
	s = clean(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	r := []rune(s)
	if len(r) > 200 {
		return string(r[:200])
	}
	return s
}
func textParts(v any, types ...string) []string {
	var out []string
	for _, part := range arr(v) {
		p := obj(part)
		for _, typ := range types {
			if str(p["type"]) == typ {
				if t := clean(str(p["text"])); t != "" {
					out = append(out, t)
				}
			}
		}
	}
	return out
}
func parseFile(path, h string) (session, error) {
	f, e := os.Open(path)
	if e != nil {
		return session{}, e
	}
	defer f.Close()
	s := session{UID: h + ":" + path, Harness: h, Path: path, NativeID: strings.TrimSuffix(filepath.Base(path), ".jsonl")}
	r := bufio.NewReader(f)
	var latest string
	var callNames = map[string]string{}
	add := func(ts, role, text string) {
		text = clean(text)
		if role == "tool" {
			text = first(text)
		}
		if role == "user" && (strings.HasPrefix(text, "<environment_context>") || strings.HasPrefix(text, "<system_reminder>") || strings.HasPrefix(text, "<local-command-") || strings.HasPrefix(text, "<command-") || strings.HasPrefix(text, "<task-notification>")) {
			return
		}
		if text == "" {
			return
		}
		if ts == "" {
			ts = latest
		}
		if ts == "" {
			ts = time.Now().UTC().Format(time.RFC3339)
		}
		s.Messages = append(s.Messages, message{Index: len(s.Messages), TS: ts, Role: role, Text: text})
		if s.Started == "" {
			s.Started = ts
		}
		s.Updated = ts
	}
	for {
		line, err := r.ReadBytes('\n')
		if len(line) > 0 {
			var d map[string]any
			if json.Unmarshal(line, &d) == nil {
				ts := str(d["timestamp"])
				if ts != "" {
					latest = ts
				}
				p := obj(d["payload"])
				m := obj(d["message"])
				switch h {
				case "claude":
					if id := str(d["sessionId"]); id != "" {
						s.NativeID = id
					}
					if cwd := str(d["cwd"]); cwd != "" {
						s.CWD = cwd
					}
					if d["isMeta"] == true || d["isSidechain"] == true || d["isCompactSummary"] == true {
						break
					}
					switch str(d["type"]) {
					case "user":
						if v, ok := m["content"].(string); ok {
							add(ts, "user", v)
						} else {
							for _, part := range arr(m["content"]) {
								x := obj(part)
								if str(x["type"]) == "text" {
									add(ts, "user", str(x["text"]))
								} else if str(x["type"]) == "tool_result" {
									name := callNames[str(x["tool_use_id"])]
									if name == "" {
										name = "tool"
									}
									t := str(x["content"])
									if t == "" {
										t = str(obj(x["content"])["text"])
									}
									add(ts, "tool", name+" · "+first(t))
								}
							}
						}
					case "assistant":
						if model := str(m["model"]); model != "" {
							s.Model = model
						}
						for _, part := range arr(m["content"]) {
							x := obj(part)
							switch str(x["type"]) {
							case "text":
								add(ts, "asst", str(x["text"]))
							case "tool_use":
								name := str(x["name"])
								callNames[str(x["id"])] = name
								input := obj(x["input"])
								t := str(input["command"])
								if t == "" {
									t = str(input["file_path"])
								}
								if t == "" {
									t = str(input["path"])
								}
								add(ts, "tool", name+" · "+first(t))
							}
						}
					}
				case "codex":
					switch str(d["type"]) {
					case "session_meta":
						s.NativeID = str(p["id"])
						s.CWD = str(p["cwd"])
						s.Started = str(p["timestamp"])
					case "turn_context":
						if x := str(p["model"]); x != "" {
							s.Model = x
						}
						if x := str(p["cwd"]); x != "" {
							s.CWD = x
						}
					case "response_item":
						switch str(p["type"]) {
						case "message":
							role := str(p["role"])
							if role == "user" || role == "assistant" {
								for _, part := range arr(p["content"]) {
									x := obj(part)
									if str(x["type"]) == "input_text" || str(x["type"]) == "output_text" {
										t := str(x["text"])
										if strings.HasPrefix(t, "<environment_context>") || strings.HasPrefix(t, "<system_reminder>") {
											continue
										}
										if role == "assistant" {
											role = "asst"
										}
										add(ts, role, t)
									}
								}
							}
						case "function_call", "custom_tool_call":
							name := str(p["name"])
							callNames[str(p["call_id"])] = name
							t := str(p["arguments"])
							if t == "" {
								t = str(obj(p["input"])["command"])
							}
							add(ts, "tool", name+" · "+first(t))
						case "function_call_output", "custom_tool_call_output":
							name := callNames[str(p["call_id"])]
							if name == "" {
								name = "tool"
							}
							add(ts, "tool", name+" · "+first(str(p["output"])))
						}
					}
				case "pi":
					switch str(d["type"]) {
					case "session":
						s.NativeID = str(d["id"])
						s.CWD = str(d["cwd"])
						s.Started = ts
					case "message":
						role := str(m["role"])
						if x := str(m["model"]); x != "" {
							s.Model = x
						}
						switch role {
						case "user", "assistant":
							if role == "assistant" {
								role = "asst"
							}
							if t, ok := m["content"].(string); ok {
								add(ts, role, t)
							} else {
								for _, part := range arr(m["content"]) {
									x := obj(part)
									if str(x["type"]) == "text" {
										add(ts, role, str(x["text"]))
									} else if str(x["type"]) == "toolCall" {
										name := str(x["name"])
										t := str(obj(x["arguments"])["command"])
										if t == "" {
											t = str(obj(x["arguments"])["path"])
										}
										add(ts, "tool", name+" · "+first(t))
									}
								}
							}
						case "toolResult":
							name := str(m["toolName"])
							for _, t := range textParts(m["content"], "text") {
								add(ts, "tool", name+" · "+first(t))
								break
							}
						}
					}
				}
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return session{}, err
		}
	}
	if len(s.Messages) == 0 {
		return session{}, errors.New("no messages")
	}
	if s.CWD == "" {
		s.CWD = filepath.Dir(path)
	}
	s.Project = filepath.Base(s.CWD)
	if s.NativeID == "" {
		s.NativeID = strings.TrimSuffix(filepath.Base(path), ".jsonl")
	}
	return s, nil
}
