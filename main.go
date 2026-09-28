package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
)

// version is overridden at release time via -ldflags "-X main.version=..."
var version = "dev"

var output io.Writer = os.Stdout

const usage = `Usage:
  kioku [flags] [query]           Search (TUI on a terminal, compact pages otherwise)
  kioku --sessions [query]        Matching sessions, ranked by best hit
  kioku show <ref|session-id>     Message context or start of session
  kioku index [--rebuild]         Sync sources and print counts
  kioku help                      Show this help

Flags: --json (one JSON page), --limit N (default 10 for pages, 300 for TUI),
       --cursor TOKEN (next page), --harness all|claude|codex|pi,
       --context N (show: before/after, default 3), --query Q (center show hit),
       --all (show: whole session), --full (show: untruncated hit),
       --no-mouse, --rebuild (index), --version, --help, -h.
Query: space means AND; "black tea" is a phrase; -word excludes;
       bare words are prefixes. Use -- to search flag-like text:
       kioku -- --help (or kioku '"help"' for the word help).
JSON: {shown,total,total_sessions,hits,next_cursor} for search;
      {shown,total,sessions,next_cursor} for --sessions;
      {harness,project,cwd,date,resume_cmd,start,end,session_total,hit_index,messages,next_cursor} for show.
      Hit fields: ref,harness,project,age,role,snippet.
      Session fields: ref,harness,project,age,hits,roles{you,asst,tool},best_ref,best.
      Show start,end,hit_index are zero-based like refs; session_total is a count.
      Show message fields: time,role,text,hit,full (when --full).
Environment: KIOKU_INDEX, KIOKU_CLAUDE_DIR, KIOKU_CODEX_DIR,
             KIOKU_PI_DIR, KIOKU_EDITOR, KIOKU_THEME=light|dark,
             KIOKU_DEBUG_TIMING=1; HOME, XDG_CACHE_HOME, VISUAL.
`

func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "kioku:", e)
		os.Exit(1)
	}
}
func timing(label string, started time.Time) {
	if os.Getenv("KIOKU_DEBUG_TIMING") == "1" {
		fmt.Fprintf(os.Stderr, "timing %s=%.2fms\n", label, float64(time.Since(started).Microseconds())/1000)
	}
}
func run() error {
	started := time.Now()
	args := os.Args[1:]
	if len(args) > 0 && args[0] == "help" {
		fmt.Fprint(output, usage)
		return nil
	}
	index := len(args) > 0 && args[0] == "index"
	show := len(args) > 0 && args[0] == "show"
	if index || show {
		args = args[1:]
	}
	fs := flag.NewFlagSet("kioku", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	rebuild := fs.Bool("rebuild", false, "rebuild index")
	jsonFlag := fs.Bool("json", false, "print JSON lines")
	limit := fs.Int("limit", 0, "maximum results")
	cursor := fs.String("cursor", "", "next page token")
	showQuery := fs.String("query", "", "locate the hit in show")
	contextSize := fs.Int("context", 3, "messages before and after")
	all := fs.Bool("all", false, "show full session")
	full := fs.Bool("full", false, "show selected message without truncation")
	sessions := fs.Bool("sessions", false, "group by session")
	noMouse := fs.Bool("no-mouse", false, "disable mouse")
	harness := fs.String("harness", "all", "all, claude, codex or pi")
	ver := fs.Bool("version", false, "print version")
	// Flags may precede or follow the query.
	var words []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			words = append(words, args[i+1:]...)
			break
		}
		if a == "--help" || a == "-h" {
			fmt.Fprint(output, usage)
			return nil
		}
		if a == "--limit" || a == "--cursor" || a == "--context" || a == "--query" {
			if i+1 == len(args) {
				return fmt.Errorf("%s requires a value", a)
			}
			if e := fs.Parse(args[i : i+2]); e != nil {
				return e
			}
			i++
			continue
		}
		if strings.HasPrefix(a, "--limit=") || strings.HasPrefix(a, "--cursor=") || strings.HasPrefix(a, "--context=") || strings.HasPrefix(a, "--query=") {
			if e := fs.Parse([]string{a}); e != nil {
				return e
			}
			continue
		}
		if a == "--harness" && i+1 < len(args) {
			*harness = args[i+1]
			i++
			continue
		}
		if strings.HasPrefix(a, "--harness=") {
			*harness = strings.TrimPrefix(a, "--harness=")
			continue
		}
		switch a {
		case "--rebuild", "--json", "--no-mouse", "--version", "--sessions", "--all", "--full":
			if e := fs.Parse([]string{a}); e != nil {
				return e
			}
		default:
			words = append(words, a)
		}
	}
	if *ver {
		fmt.Fprintln(output, version)
		return nil
	}
	oneShot := show || *sessions || *jsonFlag || *cursor != "" || !isatty.IsTerminal(os.Stdout.Fd())
	setLimit := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "limit" {
			setLimit = true
		}
	})
	if !setLimit {
		if oneShot {
			*limit = 10
		} else {
			*limit = 300
		}
	}
	if *limit < 1 {
		return fmt.Errorf("--limit must be a positive integer")
	}
	if *contextSize < 0 {
		return fmt.Errorf("--context must be nonnegative")
	}
	if show && (*sessions || len(words) != 1) {
		return fmt.Errorf("show requires one reference (and cannot use --sessions)")
	}
	if !show && *all {
		return fmt.Errorf("--all requires show")
	}
	if !show && *full {
		return fmt.Errorf("--full requires show")
	}
	if !show && *showQuery != "" {
		return fmt.Errorf("--query requires show")
	}
	if *harness != "all" && *harness != "claude" && *harness != "codex" && *harness != "pi" {
		return fmt.Errorf("invalid harness %q", *harness)
	}
	db, e := openDB()
	if e != nil {
		return e
	}
	defer db.Close()
	timing("startup", started)
	if index {
		syncStart := time.Now()
		s, e := syncIndex(db, *rebuild, nil)
		timing("sync", syncStart)
		if e != nil {
			return e
		}
		for _, h := range []string{"claude", "codex", "pi"} {
			fmt.Fprintf(output, "%s: %d messages\n", h, s.Messages[h])
		}
		fmt.Fprintf(output, "%d files, %d changed, %d skipped\n", s.Files, s.Changed, s.Skipped)
		return nil
	}
	q := strings.Join(words, " ")
	if oneShot {
		syncStart := time.Now()
		_, e = syncIndex(db, false, nil)
		timing("sync", syncStart)
		if e != nil {
			return e
		}
		mode := "hits"
		if *sessions {
			mode = "sessions"
		}
		if show {
			mode = "show"
			q = *showQuery
		}
		key := pageKey{Mode: mode, Query: q, Harness: *harness, Limit: *limit, Context: *contextSize, JSON: *jsonFlag, All: *all, Full: *full, NoMouse: *noMouse, Rebuild: *rebuild}
		if show {
			key.Ref = words[0]
		}
		offset, err := key.offset(*cursor)
		if err != nil {
			return err
		}
		ctx := context.Background()
		switch mode {
		case "show":
			page, err := compactShow(ctx, db, key, offset)
			if err != nil {
				return err
			}
			return renderShow(page, *jsonFlag)
		case "sessions":
			page, err := compactSessions(ctx, db, key, offset)
			if err != nil {
				return err
			}
			return renderSessions(page, *jsonFlag)
		default:
			page, err := compactSearch(ctx, db, key, offset)
			if err != nil {
				return err
			}
			return renderHits(page, *jsonFlag, q)
		}
	}
	rows, e := search(context.Background(), db, q, *harness, *limit)
	if e != nil {
		return e
	}
	m := newModel(db, q, *harness, rows, !*noMouse, *limit)
	options := []tea.ProgramOption{tea.WithAltScreen()}
	if !*noMouse {
		options = append(options, tea.WithMouseCellMotion())
	}
	final, e := tea.NewProgram(m, options...).Run()
	if e != nil {
		return e
	}
	fm := final.(model)
	if fm.resume != nil {
		return execSession(*fm.resume)
	}
	return nil
}
func execSession(h hit) error {
	if e := os.Chdir(h.CWD); e != nil {
		return e
	}
	var name string
	var args []string
	switch h.Harness {
	case "claude":
		name = "claude"
		args = []string{"claude", "--resume", h.SessionID}
	case "codex":
		name = "codex"
		args = []string{"codex", "resume", h.SessionID}
	case "pi":
		name = "pi"
		args = []string{"pi", "--session", h.Path}
	}
	bin, e := exec.LookPath(name)
	if e != nil {
		return e
	}
	return syscall.Exec(bin, args, os.Environ())
}
