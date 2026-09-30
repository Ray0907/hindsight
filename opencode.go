package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func opencodePath() string {
	p := os.Getenv("KIOKU_OPENCODE_DB")
	if p == "" {
		root := os.Getenv("XDG_DATA_HOME")
		if root == "" {
			root = filepath.Join(os.Getenv("HOME"), ".local/share")
		}
		p = filepath.Join(root, "opencode/opencode.db")
	}
	if strings.HasPrefix(p, "~/") {
		p = filepath.Join(os.Getenv("HOME"), strings.TrimPrefix(p, "~/"))
	}
	return p
}

type opencodeSession struct {
	session
	updated int64
	v2      bool
}
type opencodeStore struct {
	db       *sql.DB
	tx       *sql.Tx
	sessions map[string]opencodeSession
	clock    string
}

func (o *opencodeStore) close() {
	o.tx.Rollback()
	o.db.Close()
}
func loadOpencode() (*opencodeStore, error) {
	path, e := filepath.Abs(opencodePath())
	if e != nil {
		return nil, e
	}
	if _, e = os.Stat(path); os.IsNotExist(e) {
		return nil, nil
	} else if e != nil {
		return nil, e
	}
	// Do not use immutable=1: it ignores committed messages in a live WAL.
	u := url.URL{Scheme: "file", Path: path, RawQuery: "mode=ro&_query_only=1&_busy_timeout=5000"}
	db, e := sql.Open("sqlite3", u.String())
	if e != nil {
		return nil, e
	}
	tx, e := db.Begin()
	if e != nil {
		db.Close()
		return nil, e
	}
	o := &opencodeStore{db: db, tx: tx, sessions: map[string]opencodeSession{}}
	if e = o.discover(path); e != nil {
		o.close()
		return nil, e
	}
	return o, nil
}
func (o *opencodeStore) discover(path string) error {
	var v1, v2 int
	if e := o.tx.QueryRow(`SELECT count(CASE WHEN name='session' THEN 1 END), count(CASE WHEN name='session_v2' THEN 1 END) FROM sqlite_master WHERE type='table'`).Scan(&v1, &v2); e != nil {
		return e
	}
	if v1+v2 == 0 {
		return fmt.Errorf("%s: neither session nor session_v2 table found", path)
	}
	if v1 > 0 {
		var hasTime int
		if e := o.tx.QueryRow("SELECT count(*) FROM pragma_table_info('message') WHERE name='time_created'").Scan(&hasTime); e != nil {
			return e
		}
		o.clock = "m.time_created"
		if hasTime == 0 {
			o.clock = `CASE WHEN json_valid(m.data) THEN CAST(COALESCE(json_extract(m.data,'$.time.created'),json_extract(m.data,'$.time'),0) AS INTEGER) ELSE 0 END`
		}
	}
	// Separate MAX lookups can use timestamp indexes; unchanged sessions never read parts.
	latestV1 := "COALESCE((SELECT max(" + o.clock + ") FROM message m WHERE m.session_id=s.id),0)"
	latestV2 := `max(COALESCE((SELECT max(time_created) FROM session_message WHERE session_id=s.id),0),COALESCE((SELECT max(time_updated) FROM session_message WHERE session_id=s.id),0))`
	for _, layout := range []struct {
		enabled       int
		table, latest string
		v2            bool
	}{{v1, "session", latestV1, false}, {v2, "session_v2", latestV2, true}} {
		if layout.enabled == 0 {
			continue
		}
		filter := ""
		if !layout.v2 && v2 > 0 {
			// Even a v2 subagent/empty session supersedes its v1 counterpart.
			filter = " AND NOT EXISTS(SELECT 1 FROM session_v2 WHERE id=s.id)"
		}
		rows, e := o.tx.Query(`SELECT s.id, COALESCE(s.directory,''), s.time_created,
max(s.time_updated,` + layout.latest + `) FROM ` + layout.table + ` s
WHERE (s.parent_id IS NULL OR s.parent_id='')` + filter)
		if e != nil {
			return e
		}
		for rows.Next() {
			var id, cwd string
			var created, updated int64
			if e = rows.Scan(&id, &cwd, &created, &updated); e != nil {
				break
			}
			p := path + "#" + id
			o.sessions[p] = opencodeSession{session: session{UID: "opencode:" + p, Harness: "opencode", NativeID: id, Path: p, CWD: cwd, Project: filepath.Base(cwd), Started: opencodeTime(created), Updated: opencodeTime(updated)}, updated: updated, v2: layout.v2}
		}
		if e == nil {
			e = rows.Err()
		}
		rows.Close()
		if e != nil {
			return e
		}
	}
	return nil
}
func opencodeTime(ms int64) string { return time.UnixMilli(ms).UTC().Format(time.RFC3339Nano) }

func (o *opencodeStore) parse(src opencodeSession) (session, error) {
	s := src.session
	q := `SELECT m.data,COALESCE(p.data,'{}'),` + o.clock + `,'' FROM message m LEFT JOIN part p ON p.message_id=m.id WHERE m.session_id=? ORDER BY ` + o.clock + `,m.id,p.id`
	if src.v2 {
		q = "SELECT data,'',time_created,type FROM session_message WHERE session_id=? ORDER BY seq,id"
	}
	rows, e := o.tx.Query(q, s.NativeID)
	if e != nil {
		return s, e
	}
	defer rows.Close()
	for rows.Next() {
		var data, part, typ string
		var ts int64
		if e = rows.Scan(&data, &part, &ts, &typ); e != nil {
			return s, e
		}
		var m, p map[string]any
		if json.Unmarshal([]byte(data), &m) != nil {
			continue
		}
		if model := str(m["modelID"]); model != "" {
			s.Model = model
		}
		role, text, self := typ, str(m["text"]), false
		if !src.v2 {
			if json.Unmarshal([]byte(part), &p) != nil {
				continue
			}
			role, text = str(m["role"]), str(p["text"])
			switch str(p["type"]) {
			case "text":
			case "tool":
				role = "tool"
				state := obj(p["state"])
				input := obj(state["input"])
				text = toolCommand(state["input"])
				self = selfCommandRE.MatchString(text)
				if text == "" {
					text = str(input["path"])
				}
				if text == "" {
					text = str(input["file_path"])
				}
				if text == "" {
					text = str(state["output"])
				}
				text = str(p["tool"]) + " · " + first(text)
			default:
				continue
			}
		} else if strings.HasPrefix(role, "tool") {
			role = "tool"
			name := str(m["tool"])
			if name == "" {
				name = "tool"
			}
			text = name + " · " + first(text)
		}
		switch role {
		case "assistant":
			role = "asst"
		case "user", "tool":
		default:
			continue
		}
		text = clean(text)
		if text == "" || role == "user" && injectedUserText(text) {
			continue
		}
		stamp := s.Started
		if ts != 0 {
			stamp = opencodeTime(ts)
		}
		s.Messages = append(s.Messages, message{Index: len(s.Messages), TS: stamp, Role: role, Text: text, Self: self})
	}
	if e = rows.Err(); e != nil {
		return s, e
	}
	if len(s.Messages) == 0 {
		return s, errNoMessages
	}
	return s, nil
}
