package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func parseCursor(path string, updated int64) (session, error) {
	s := session{UID: "cursor:" + path, Harness: "cursor", NativeID: filepath.Base(filepath.Dir(path)), Path: path, Updated: time.Unix(0, updated).UTC().Format(time.RFC3339Nano)}
	data, e := os.ReadFile(path)
	if e != nil {
		return s, e
	}
	var meta struct {
		CWD         string `json:"cwd"`
		CreatedAtMs int64  `json:"createdAtMs"`
	}
	if e = json.Unmarshal(data, &meta); e != nil {
		return s, e
	}
	if meta.CWD == "" {
		return s, errNoMessages
	}
	s.CWD, s.Project = meta.CWD, filepath.Base(meta.CWD)
	s.Started = time.UnixMilli(meta.CreatedAtMs).UTC().Format(time.RFC3339Nano)
	store, e := filepath.Abs(filepath.Join(filepath.Dir(path), "store.db"))
	if e != nil {
		return s, e
	}
	u := url.URL{Scheme: "file", Path: store, RawQuery: "mode=ro&_query_only=1&_busy_timeout=5000"}
	db, e := sql.Open("sqlite3", u.String())
	if e != nil {
		return s, e
	}
	defer db.Close()
	// Cursor records no message order; rowid is only an insertion-order approximation.
	rows, e := db.Query("SELECT data FROM blobs ORDER BY rowid")
	if e != nil {
		return s, e
	}
	defer rows.Close()
	for rows.Next() {
		if e = rows.Scan(&data); e != nil {
			return s, e
		}
		data = bytes.TrimSpace(data)
		if len(data) == 0 || data[0] != '{' {
			continue // The graph's undocumented binary blobs are not messages.
		}
		var m struct {
			Role    string `json:"role"`
			Content any    `json:"content"`
		}
		if json.Unmarshal(data, &m) != nil || m.Role != "user" && m.Role != "assistant" {
			continue
		}
		text := str(m.Content)
		if blocks, ok := m.Content.([]any); ok {
			var texts []string
			for _, block := range blocks {
				t, ok := block.(string)
				if !ok {
					t, ok = obj(block)["text"].(string)
				}
				if ok {
					texts = append(texts, t)
				}
			}
			text = strings.Join(texts, "\n")
		}
		text = clean(text)
		if text == "" {
			continue
		}
		if m.Role == "assistant" {
			m.Role = "asst"
		}
		s.Messages = append(s.Messages, message{Index: len(s.Messages), TS: s.Updated, Role: m.Role, Text: text})
	}
	if e = rows.Err(); e != nil {
		return s, e
	}
	if len(s.Messages) == 0 {
		return s, errNoMessages
	}
	return s, nil
}
