package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "github.com/Ray0907/hindsight/internal/cjk"
	_ "github.com/mattn/go-sqlite3"
)

func roots() map[string]string {
	home := os.Getenv("HOME")
	out := map[string]string{}
	for _, p := range []struct{ h, env, rel string }{{"claude", "HINDSIGHT_CLAUDE_DIR", ".claude/projects"}, {"codex", "HINDSIGHT_CODEX_DIR", ".codex/sessions"}, {"pi", "HINDSIGHT_PI_DIR", ".pi/agent/sessions"}} {
		out[p.h] = os.Getenv(p.env)
		if out[p.h] == "" {
			out[p.h] = filepath.Join(home, p.rel)
		}
	}
	return out
}
func indexPath() string {
	if p := os.Getenv("HINDSIGHT_INDEX"); p != "" {
		return p
	}
	root := os.Getenv("XDG_CACHE_HOME")
	if root == "" {
		root = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(root, "hindsight", "index.db")
}
func openDB() (*sql.DB, error) {
	path := indexPath()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	db, e := sql.Open("sqlite3", path)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	_, e = db.Exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS meta (schema_version INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (uid TEXT PRIMARY KEY, harness TEXT, native_id TEXT, path TEXT, cwd TEXT, project TEXT, model TEXT, started TEXT, updated TEXT);
CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, session_uid TEXT, idx INTEGER, ts TEXT, role TEXT, text TEXT);
CREATE INDEX IF NOT EXISTS messages_session ON messages(session_uid,idx);
CREATE TABLE IF NOT EXISTS sources (path TEXT PRIMARY KEY, mtime INTEGER, size INTEGER);
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(text, content='messages',content_rowid='id',tokenize='cjk unigram 1 remove_diacritics 2');
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN INSERT INTO messages_fts(rowid,text) VALUES(new.id,new.text); END;
CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN INSERT INTO messages_fts(messages_fts,rowid,text) VALUES('delete',old.id,old.text); END;
INSERT INTO meta(schema_version) SELECT 1 WHERE NOT EXISTS(SELECT 1 FROM meta);`)
	if e != nil {
		db.Close()
		return nil, e
	}
	return db, nil
}

type syncStats struct {
	Files, Changed, Skipped int
	Messages                map[string]int
}

func syncIndex(db *sql.DB, rebuild bool, progress func(int, int)) (syncStats, error) {
	stats := syncStats{Messages: map[string]int{}}
	files := map[string]string{}
	for h, root := range roots() {
		err := filepath.WalkDir(root, func(p string, d os.DirEntry, e error) error {
			if e != nil {
				stats.Skipped++
				return nil
			}
			if !d.IsDir() && strings.HasSuffix(p, ".jsonl") {
				files[p] = h
			}
			return nil
		})
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			stats.Skipped++
		}
	}
	stats.Files = len(files)
	tx, e := db.Begin()
	if e != nil {
		return stats, e
	}
	defer tx.Rollback()
	if rebuild {
		for _, table := range []string{"messages", "sessions", "sources"} {
			if _, e = tx.Exec("DELETE FROM " + table); e != nil {
				return stats, e
			}
		}
	}
	old := map[string]struct{ mtime, size int64 }{}
	rows, e := tx.Query("SELECT path,mtime,size FROM sources")
	if e != nil {
		return stats, e
	}
	for rows.Next() {
		var p string
		var v struct{ mtime, size int64 }
		if rows.Scan(&p, &v.mtime, &v.size) == nil {
			old[p] = v
		}
	}
	rows.Close()
	for p := range old {
		if _, ok := files[p]; !ok {
			if e = removeSource(tx, p); e != nil {
				return stats, e
			}
		}
	}
	paths := make([]string, 0, len(files))
	for p := range files {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	for i, p := range paths {
		if progress != nil {
			progress(i+1, len(paths))
		}
		info, err := os.Stat(p)
		if err != nil {
			stats.Skipped++
			continue
		}
		mtime := info.ModTime().UnixNano()
		size := info.Size()
		if v, ok := old[p]; ok && v.mtime == mtime && v.size == size {
			continue
		}
		s, err := parseFile(p, files[p])
		if err != nil {
			stats.Skipped++
			continue
		}
		if e = removeSource(tx, p); e != nil {
			return stats, e
		}
		if _, e = tx.Exec("INSERT INTO sessions VALUES(?,?,?,?,?,?,?,?,?)", s.UID, s.Harness, s.NativeID, s.Path, s.CWD, s.Project, s.Model, s.Started, s.Updated); e != nil {
			return stats, e
		}
		for _, m := range s.Messages {
			if _, e = tx.Exec("INSERT INTO messages(session_uid,idx,ts,role,text) VALUES(?,?,?,?,?)", s.UID, m.Index, m.TS, m.Role, m.Text); e != nil {
				return stats, e
			}
		}
		if _, e = tx.Exec("INSERT INTO sources VALUES(?,?,?)", p, mtime, size); e != nil {
			return stats, e
		}
		stats.Changed++
	}
	if e = tx.Commit(); e != nil {
		return stats, e
	}
	rows, e = db.Query("SELECT s.harness,count(m.id) FROM sessions s LEFT JOIN messages m ON s.uid=m.session_uid GROUP BY s.harness")
	if e != nil {
		return stats, e
	}
	defer rows.Close()
	for rows.Next() {
		var h string
		var n int
		if rows.Scan(&h, &n) == nil {
			stats.Messages[h] = n
		}
	}
	return stats, rows.Err()
}
func removeSource(tx *sql.Tx, p string) error {
	for _, q := range []string{"DELETE FROM messages WHERE session_uid IN (SELECT uid FROM sessions WHERE path=?)", "DELETE FROM sessions WHERE path=?", "DELETE FROM sources WHERE path=?"} {
		if _, e := tx.Exec(q, p); e != nil {
			return e
		}
	}
	return nil
}
func age(ts string) string {
	t, e := time.Parse(time.RFC3339Nano, ts)
	if e != nil {
		return ""
	}
	d := time.Since(t)
	if d < time.Hour {
		return fmt.Sprintf("%dm", max(0, int(d.Minutes())))
	}
	if d < 24*time.Hour {
		return fmt.Sprintf("%dh", int(d.Hours()))
	}
	if d < 7*24*time.Hour {
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
	return fmt.Sprintf("%dw", int(d.Hours()/168))
}
