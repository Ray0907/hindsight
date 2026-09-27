package main

import (
	"database/sql"
	"encoding/json"
	"regexp"
	"strings"
	"unicode"
)

var termsRE = regexp.MustCompile(`(-?)"([^"]+)"|(-?)(\S+)`)

type term struct {
	Word     string
	Phrase   bool
	Negative bool
}

func terms(q string) []term {
	var out []term
	for _, m := range termsRE.FindAllStringSubmatch(q, -1) {
		t := m[2] + m[4]
		neg := m[1]+m[3] == "-" && !strings.HasPrefix(t, "-")
		if m[1]+m[3] == "-" && !neg {
			t = "-" + t
		}
		out = append(out, term{t, m[2] != "", neg})
	}
	return out
}
func toFTS(q string) string {
	var pos, neg []string
	for _, t := range terms(q) {
		w := `"` + strings.ReplaceAll(t.Word, `"`, ` `) + `"`
		if !t.Phrase {
			w += "*"
		}
		if t.Negative {
			neg = append(neg, w)
		} else {
			pos = append(pos, w)
		}
	}
	if len(pos) == 0 {
		return ""
	}
	out := strings.Join(pos, " AND ")
	for _, n := range neg {
		out += " NOT " + n
	}
	return out
}

type hit struct {
	Harness   string `json:"harness"`
	SessionID string `json:"session_id"`
	Project   string `json:"project"`
	CWD       string `json:"cwd"`
	TS        string `json:"ts"`
	Role      string `json:"role"`
	Text      string `json:"text"`
	Snippet   string `json:"snippet"`
	ResumeCmd string `json:"resume_cmd"`
	Path      string `json:"path"`
	UID       string `json:"-"`
	Index     int    `json:"-"`
	ID        int64  `json:"-"`
}

func resumeCmd(h, id, path string) string {
	switch h {
	case "claude":
		return "claude --resume " + id
	case "codex":
		return "codex resume " + id
	default:
		return "pi --session " + path
	}
}
func search(db *sql.DB, q, harness string) ([]hit, error) {
	match := toFTS(q)
	sqlq := `SELECT s.uid,s.harness,s.native_id,s.project,s.cwd,s.path,m.id,m.idx,m.ts,m.role,m.text FROM sessions s JOIN messages m ON s.uid=m.session_uid `
	args := []any{}
	if match != "" {
		sqlq += `JOIN messages_fts ON messages_fts.rowid=m.id WHERE messages_fts MATCH ? `
		args = append(args, match)
	} else {
		sqlq += `WHERE m.idx=(SELECT max(idx) FROM messages WHERE session_uid=s.uid) `
	}
	if harness != "" && harness != "all" {
		sqlq += `AND s.harness=? `
		args = append(args, harness)
	}
	if match != "" {
		sqlq += `ORDER BY bm25(messages_fts),m.ts DESC,m.id DESC LIMIT 300`
	} else {
		sqlq += `ORDER BY m.ts DESC,m.id DESC LIMIT 300`
	}
	rows, e := db.Query(sqlq, args...)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []hit{}
	for rows.Next() {
		var x hit
		if e = rows.Scan(&x.UID, &x.Harness, &x.SessionID, &x.Project, &x.CWD, &x.Path, &x.ID, &x.Index, &x.TS, &x.Role, &x.Text); e != nil {
			return nil, e
		}
		x.Snippet = snippet(x.Text, terms(q))
		x.ResumeCmd = resumeCmd(x.Harness, x.SessionID, x.Path)
		out = append(out, x)
	}
	return out, rows.Err()
}
func transcript(db *sql.DB, uid string) ([]message, error) {
	rows, e := db.Query("SELECT id,idx,ts,role,text FROM messages WHERE session_uid=? ORDER BY idx", uid)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []message{}
	for rows.Next() {
		var m message
		if e = rows.Scan(&m.ID, &m.Index, &m.TS, &m.Role, &m.Text); e != nil {
			return nil, e
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
func snippet(text string, ts []term) string {
	text = strings.ReplaceAll(text, "\n", " ")
	r := []rune(text)
	start := 0
	for _, t := range ts {
		if t.Negative {
			continue
		}
		i := strings.Index(strings.ToLower(text), strings.ToLower(t.Word))
		if i >= 0 {
			start = len([]rune(text[:i])) - 12
			if start < 0 {
				start = 0
			}
			if start > 0 && start < len(r) && unicode.IsLetter(r[start-1]) && !isCJK(r[start]) {
				for start > 0 && !unicode.IsSpace(r[start-1]) && !isCJK(r[start-1]) {
					start--
				}
			}
			break
		}
	}
	if start >= len(r) {
		start = 0
	}
	if start > 0 {
		return "…" + string(r[start:])
	}
	return text
}
func isCJK(r rune) bool {
	return unicode.In(r, unicode.Han, unicode.Hiragana, unicode.Katakana, unicode.Hangul)
}
func jsonLines(rows []hit) error {
	enc := json.NewEncoder(output)
	enc.SetEscapeHTML(false)
	for _, r := range rows {
		if e := enc.Encode(r); e != nil {
			return e
		}
	}
	return nil
}
