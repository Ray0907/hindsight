package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"math"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/mattn/go-runewidth"
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
func search(ctx context.Context, db *sql.DB, q, harness string) ([]hit, error) {
	match := toFTS(q)
	started := time.Now()
	var sqlq string
	args := []any{}
	if match == "" {
		sqlq = `SELECT s.uid,s.harness,s.native_id,s.project,s.cwd,s.path,m.id,m.idx,m.ts,m.role,m.text FROM sessions s JOIN messages m ON s.uid=m.session_uid WHERE m.idx=(SELECT max(idx) FROM messages WHERE session_uid=s.uid) `
		if harness != "" && harness != "all" {
			sqlq += `AND s.harness=? `
			args = append(args, harness)
		}
		sqlq += `ORDER BY m.ts DESC,m.id DESC LIMIT 300`
	} else {
		sqlq = `SELECT messages_fts.rowid FROM messages_fts WHERE messages_fts MATCH ? `
		args = append(args, match)
		if harness != "" && harness != "all" {
			sqlq = `SELECT messages_fts.rowid FROM messages_fts JOIN messages cm ON cm.id=messages_fts.rowid JOIN sessions cs ON cs.uid=cm.session_uid WHERE messages_fts MATCH ? AND cs.harness=? `
			args = append(args, harness)
		}
		sqlq += `ORDER BY messages_fts.rowid DESC LIMIT 320`
	}
	rows, e := db.QueryContext(ctx, sqlq, args...)
	if e != nil {
		return nil, e
	}
	out := []hit{}
	ids := []any{}
	if match == "" {
		for rows.Next() {
			var x hit
			if e = rows.Scan(&x.UID, &x.Harness, &x.SessionID, &x.Project, &x.CWD, &x.Path, &x.ID, &x.Index, &x.TS, &x.Role, &x.Text); e != nil {
				break
			}
			out = append(out, x)
		}
	} else {
		for rows.Next() {
			var id int64
			if e = rows.Scan(&id); e != nil {
				break
			}
			ids = append(ids, id)
		}
	}
	if e == nil {
		e = rows.Err()
	}
	rows.Close()
	timing("query", started)
	if e != nil {
		return nil, e
	}
	if e = ctx.Err(); e != nil {
		return nil, e
	}
	if match != "" && len(ids) > 0 {
		started = time.Now()
		sqlq = `SELECT s.uid,s.harness,s.native_id,s.project,s.cwd,s.path,m.id,m.idx,m.ts,m.role,m.text FROM messages m JOIN sessions s ON s.uid=m.session_uid WHERE m.id IN (` + strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",") + `)`
		rows, e = db.QueryContext(ctx, sqlq, ids...)
		if e != nil {
			return nil, e
		}
		for rows.Next() {
			var x hit
			if e = rows.Scan(&x.UID, &x.Harness, &x.SessionID, &x.Project, &x.CWD, &x.Path, &x.ID, &x.Index, &x.TS, &x.Role, &x.Text); e != nil {
				break
			}
			out = append(out, x)
		}
		if e == nil {
			e = rows.Err()
		}
		rows.Close()
		if e != nil {
			return nil, e
		}
		if e = ctx.Err(); e != nil {
			return nil, e
		}
		rankHits(out, terms(q))
		if len(out) > 300 {
			out = out[:300]
		}
		timing("hydrate", started)
	}
	started = time.Now()
	ts := terms(q)
	for i := range out {
		if i%16 == 0 {
			if e = ctx.Err(); e != nil {
				return nil, e
			}
		}
		out[i].Snippet = snippet(out[i].Text, ts)
		out[i].ResumeCmd = resumeCmd(out[i].Harness, out[i].SessionID, out[i].Path)
	}
	timing("snippet", started)
	return out, nil
}

// BM25 over a bounded newest-hit sample keeps common prefixes independent of corpus size.
func rankHits(rows []hit, ts []term) {
	if len(rows) < 2 {
		return
	}
	words := []string{}
	for _, t := range ts {
		if !t.Negative {
			words = append(words, strings.ToLower(t.Word))
		}
	}
	if len(words) == 0 {
		return
	}
	type scored struct {
		row    hit
		tf     []int
		length int
		score  float64
	}
	items := make([]scored, len(rows))
	df := make([]int, len(words))
	total := 0
	for i, r := range rows {
		lower := strings.ToLower(r.Text)
		n := utf8.RuneCountInString(r.Text)
		items[i] = scored{row: r, tf: make([]int, len(words)), length: n}
		total += n
		for j, w := range words {
			items[i].tf[j] = strings.Count(lower, w)
			if items[i].tf[j] > 0 {
				df[j]++
			}
		}
	}
	avg := float64(total) / float64(len(rows))
	if avg == 0 {
		avg = 1
	}
	for i := range items {
		for j, tf := range items[i].tf {
			if tf == 0 {
				continue
			}
			idf := math.Log(1 + (float64(len(rows)-df[j])+0.5)/(float64(df[j])+0.5))
			f := float64(tf)
			items[i].score += idf * f * 2.2 / (f + 1.2*(0.25+0.75*float64(items[i].length)/avg))
		}
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].score != items[j].score {
			return items[i].score > items[j].score
		}
		if items[i].row.TS != items[j].row.TS {
			return items[i].row.TS > items[j].row.TS
		}
		return items[i].row.ID > items[j].row.ID
	})
	for i := range rows {
		rows[i] = items[i].row
	}
}
func transcript(ctx context.Context, db *sql.DB, uid string) ([]message, error) {
	rows, e := db.QueryContext(ctx, "SELECT id,idx,ts,role,text FROM messages WHERE session_uid=? ORDER BY idx", uid)
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
		at := strings.Index(strings.ToLower(text), strings.ToLower(t.Word))
		if at >= 0 {
			start = len([]rune(text[:at]))
		} else if found := positions(r, t.Word); len(found) > 0 {
			start = found[0]
		} else {
			continue
		}
		for cells := 0; start > 0 && cells < 12; {
			start--
			cells += runewidth.RuneWidth(r[start])
		}
		if start > 0 && start < len(r) && unicode.IsLetter(r[start-1]) && !isCJK(r[start]) {
			for start > 0 && !unicode.IsSpace(r[start-1]) && !isCJK(r[start-1]) {
				start--
			}
		}
		break
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
