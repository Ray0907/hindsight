package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func editor() (string, []string) {
	for _, s := range []string{os.Getenv("KIOKU_EDITOR"), os.Getenv("VISUAL")} {
		if s != "" {
			return s, strings.Fields(s)
		}
	}
	for _, s := range []string{"zed", "cursor", "code", "subl"} {
		if p, e := exec.LookPath(s); e == nil {
			return s, []string{p}
		}
	}
	for _, a := range []struct{ app, label string }{{"Zed.app", "Zed"}, {"Cursor.app", "Cursor"}, {"Visual Studio Code.app", "Visual Studio Code"}, {"Sublime Text.app", "Sublime Text"}} {
		for _, root := range []string{"/Applications", filepath.Join(os.Getenv("HOME"), "Applications")} {
			if _, e := os.Stat(filepath.Join(root, a.app)); e == nil {
				return a.label, []string{"open", "-a", a.label}
			}
		}
	}
	return "Finder", []string{"open"}
}
func openProject(dir string) string {
	label, argv := editor()
	if len(argv) == 0 {
		return "no editor configured"
	}
	if _, e := os.Stat(dir); e != nil {
		return "directory no longer exists: " + dir
	}
	cmd := exec.Command(argv[0], append(argv[1:], dir)...)
	if e := cmd.Start(); e != nil {
		return e.Error()
	}
	go cmd.Wait()
	return fmt.Sprintf("%s opened %s in %s", time.Now().Format("15:04"), dir, label)
}
func copyCommand(s string) string {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(s)
	e := cmd.Run() // OSC 52 also supports remote terminals; emitted outside Bubble Tea's frame.
	fmt.Fprintf(os.Stderr, "\x1b]52;c;%s\a", base64.StdEncoding.EncodeToString([]byte(s)))
	if e != nil {
		return e.Error()
	}
	return fmt.Sprintf("%s copied: %s", time.Now().Format("15:04"), s)
}
