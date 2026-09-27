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

const version = "0.1.0"

var output io.Writer = os.Stdout

func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "hindsight:", e)
		os.Exit(1)
	}
}
func timing(label string, started time.Time) {
	if os.Getenv("HINDSIGHT_DEBUG_TIMING") == "1" {
		fmt.Fprintf(os.Stderr, "timing %s=%.2fms\n", label, float64(time.Since(started).Microseconds())/1000)
	}
}
func run() error {
	started := time.Now()
	args := os.Args[1:]
	index := len(args) > 0 && args[0] == "index"
	if index {
		args = args[1:]
	}
	fs := flag.NewFlagSet("hindsight", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	rebuild := fs.Bool("rebuild", false, "rebuild index")
	jsonFlag := fs.Bool("json", false, "print JSON lines")
	noMouse := fs.Bool("no-mouse", false, "disable mouse")
	harness := fs.String("harness", "all", "all, claude, codex or pi")
	ver := fs.Bool("version", false, "print version")
	// Flags may precede or follow the query.
	var words []string
	for i := 0; i < len(args); i++ {
		a := args[i]
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
		case "--rebuild", "--json", "--no-mouse", "--version":
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
	if *jsonFlag || !isatty.IsTerminal(os.Stdout.Fd()) {
		syncStart := time.Now()
		_, e = syncIndex(db, false, nil)
		timing("sync", syncStart)
		if e != nil {
			return e
		}
		rows, e := search(context.Background(), db, q, *harness)
		if e != nil {
			return e
		}
		renderStart := time.Now()
		e = jsonLines(rows)
		timing("render", renderStart)
		return e
	}
	rows, e := search(context.Background(), db, q, *harness)
	if e != nil {
		return e
	}
	m := newModel(db, q, *harness, rows, !*noMouse)
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
