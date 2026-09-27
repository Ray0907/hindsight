package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"

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
func run() error {
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
		if strings.HasPrefix(a, "--") {
			if e := fs.Parse([]string{a}); e != nil {
				return e
			}
		} else {
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
	if index {
		s, e := syncIndex(db, *rebuild, nil)
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
		if _, e = syncIndex(db, false, nil); e != nil {
			return e
		}
		rows, e := search(db, q, *harness)
		if e != nil {
			return e
		}
		return jsonLines(rows)
	}
	rows, e := search(db, q, *harness)
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
