package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"github.com/muesli/termenv"
	"github.com/rivo/uniseg"
	"golang.org/x/text/unicode/norm"
)

type palette struct {
	ink, hit, muted, rule, claude, codex, pi, selbg, fg string
	pens                                                [3]string
}

var light = palette{"#1d3e66", "#b6322d", "#606a74", "#798898", "#8d5d1c", "#147175", "#3b723e", "#eaf1fa", "", [3]string{"#fde89a", "#bdfac8", "#ffe0f2"}}
var dark = palette{"#c0d3eb", "#f6857a", "#95a0ab", "#6f7e8d", "#ddae6c", "#76c7cc", "#8fc990", "#202730", "", [3]string{"#3c3207", "#193b22", "#492537"}}

type pen struct {
	word  string
	color int
}
type model struct {
	db                               *sql.DB
	q                                string
	harness                          string
	rows                             []hit
	messages                         []message
	hitIndex                         map[int]bool
	sel, cursor, width, height       int
	focus, full, prompt, help, mouse bool
	pens                             []pen
	status                           string
	revision                         int
	progress                         string
	resume                           *hit
	pal                              palette
	offset                           int
	cancel, loadCancel               context.CancelFunc
	loadRevision                     int
	initial                          tea.Cmd
}
type resultMsg struct {
	revision int
	rows     []hit
	err      error
}
type loadMsg struct {
	revision int
	messages []message
	hits     map[int]bool
	err      error
}
type syncMsg struct {
	done     bool
	progress string
	err      error
}
type debounce int

func newModel(db *sql.DB, q, h string, rows []hit, mouse bool) model {
	p := light
	if os.Getenv("HINDSIGHT_THEME") == "dark" || os.Getenv("HINDSIGHT_THEME") == "" && termenv.HasDarkBackground() {
		p = dark
	}
	m := model{db: db, q: q, harness: h, rows: rows, mouse: mouse, pal: p, width: 80, height: 24, cursor: -1, focus: true}
	m.initial = m.requestLoad()
	return m
}
func (m model) Init() tea.Cmd { return tea.Batch(startSync(), m.initial) }
func startSync() tea.Cmd {
	ch := make(chan syncMsg, 32)
	go func() {
		db, err := openDB()
		if err != nil {
			ch <- syncMsg{done: true, err: err}
			close(ch)
			return
		}
		defer db.Close()
		_, err = syncIndex(db, false, func(i, n int) {
			if i == 1 || i == n || i%25 == 0 {
				select {
				case ch <- syncMsg{progress: fmt.Sprintf("indexing %d/%d", i, n)}:
				default:
				}
			}
		})
		ch <- syncMsg{done: true, err: err}
		close(ch)
	}()
	return waitSync(ch)
}
func waitSync(ch <-chan syncMsg) tea.Cmd {
	return func() tea.Msg {
		x, ok := <-ch
		if !ok {
			return nil
		}
		return syncEnvelope{x, ch}
	}
}

type syncEnvelope struct {
	x  syncMsg
	ch <-chan syncMsg
}

func queryCmd(ctx context.Context, db *sql.DB, q, h string, rev int) tea.Cmd {
	return func() tea.Msg { rows, e := search(ctx, db, q, h); return resultMsg{rev, rows, e} }
}
func (m *model) requestQuery() tea.Cmd {
	if m.cancel != nil {
		m.cancel()
	}
	if m.loadCancel != nil {
		m.loadCancel()
	}
	m.loadRevision++
	m.messages = nil
	m.hitIndex = map[int]bool{}
	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel
	return queryCmd(ctx, m.db, m.q, m.harness, m.revision)
}
func (m *model) requestLoad() tea.Cmd {
	if m.loadCancel != nil {
		m.loadCancel()
	}
	m.loadRevision++
	m.messages = nil
	m.hitIndex = map[int]bool{}
	m.cursor = -1
	if m.sel >= len(m.rows) {
		m.sel = max(0, len(m.rows)-1)
	}
	if m.sel < m.offset {
		m.offset = m.sel
	}
	if m.sel >= m.offset+m.listHeight() {
		m.offset = m.sel - m.listHeight() + 1
	}
	if len(m.rows) == 0 {
		return nil
	}
	selected := m.rows[m.sel]
	m.cursor = selected.Index
	ctx, cancel := context.WithCancel(context.Background())
	m.loadCancel = cancel
	rev := m.loadRevision
	q := m.q
	return func() tea.Msg {
		msgs, e := transcript(ctx, m.db, selected.UID)
		hits := map[int]bool{}
		if e == nil && toFTS(q) != "" {
			rows, err := m.db.QueryContext(ctx, `SELECT m.idx FROM messages_fts JOIN messages m ON m.id=messages_fts.rowid WHERE messages_fts MATCH ? AND m.session_uid=?`, toFTS(q), selected.UID)
			if err == nil {
				for rows.Next() {
					var i int
					if rows.Scan(&i) == nil {
						hits[i] = true
					}
				}
				e = rows.Err()
				rows.Close()
			} else {
				e = err
			}
		}
		return loadMsg{rev, msgs, hits, e}
	}
}
func (m *model) refresh() tea.Cmd {
	m.revision++
	if m.cancel != nil {
		m.cancel()
	}
	if m.loadCancel != nil {
		m.loadCancel()
	}
	m.loadRevision++
	m.messages = nil
	m.hitIndex = map[int]bool{}
	return tea.Tick(30*time.Millisecond, func(time.Time) tea.Msg { return debounce(m.revision) })
}
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch x := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = x.Width
		m.height = x.Height
	case syncEnvelope:
		m.progress = x.x.progress
		if x.x.done {
			m.progress = ""
			if x.x.err != nil {
				m.status = x.x.err.Error()
			}
			return m, m.requestQuery()
		}
		return m, waitSync(x.ch)
	case debounce:
		if int(x) != m.revision {
			return m, nil
		}
		return m, m.requestQuery()
	case resultMsg:
		if x.revision == m.revision {
			if x.err != nil {
				if x.err != context.Canceled {
					m.status = x.err.Error()
				}
			} else {
				m.rows = x.rows
				m.sel = 0
				return m, m.requestLoad()
			}
		}
	case loadMsg:
		if x.revision == m.loadRevision {
			if x.err != nil {
				if x.err != context.Canceled {
					m.status = x.err.Error()
				}
			} else {
				m.messages = x.messages
				m.hitIndex = x.hits
			}
		}
	case tea.MouseMsg:
		return m.mouseUpdate(x)
	case tea.KeyMsg:
		key := x.String()
		if key == "ctrl+c" {
			if m.cancel != nil {
				m.cancel()
			}
			if m.loadCancel != nil {
				m.loadCancel()
			}
			return m, tea.Quit
		}
		if m.prompt {
			switch key {
			case "esc":
				m.prompt = false
				m.status = ""
			case "enter":
				w := strings.TrimSpace(m.status)
				if w != "" {
					exists := false
					for _, p := range m.pens {
						if p.word == w {
							exists = true
						}
					}
					if !exists {
						m.pens = append(m.pens, pen{w, len(m.pens) % 3})
					}
				}
				m.status = ""
				m.prompt = false
			case "backspace":
				m.status = trimLast(m.status)
			default:
				if x.Type == tea.KeyRunes {
					m.status += string(x.Runes)
				}
			}
			return m, nil
		}
		if key == "tab" || key == "shift+tab" {
			hs := []string{"all", "claude", "codex", "pi"}
			for i, h := range hs {
				if h == m.harness {
					step := 1
					if key == "shift+tab" {
						step = 3
					}
					m.harness = hs[(i+step)%4]
					break
				}
			}
			m.sel = 0
			m.revision++
			return m, m.requestQuery()
		}
		if key == "enter" {
			if len(m.rows) > 0 {
				r := m.rows[m.sel]
				if _, e := os.Stat(r.CWD); e != nil {
					m.status = "directory no longer exists: " + r.CWD
				} else {
					m.resume = &r
					return m, tea.Quit
				}
			}
			return m, nil
		}
		if m.focus {
			switch key {
			case "down", "esc":
				m.focus = false
			case "backspace":
				m.q = trimLast(m.q)
				m.status = ""
				return m, m.refresh()
			case "ctrl+u":
				m.q = ""
				return m, m.refresh()
			default:
				if x.Type == tea.KeyRunes {
					m.q += string(x.Runes)
					m.status = ""
					return m, m.refresh()
				}
			}
			return m, nil
		}
		if m.help && key != "?" {
			m.help = false
			return m, nil
		}
		switch key {
		case "esc":
			if m.help {
				m.help = false
				return m, nil
			}
			return m, tea.Quit
		case "up", "k":
			if m.sel == 0 {
				m.focus = true
			} else {
				m.sel--
				return m, m.requestLoad()
			}
		case "down", "j":
			if m.sel+1 < len(m.rows) {
				m.sel++
				return m, m.requestLoad()
			}
		case "/":
			m.focus = true
		case "n", "N":
			m.jump(key == "n")
		case "h":
			m.prompt = true
			m.status = ""
		case "H":
			m.pens = nil
		case "v":
			m.full = !m.full
		case "?":
			m.help = !m.help
		case "o":
			if len(m.rows) > 0 {
				m.status = openProject(m.rows[m.sel].CWD)
			}
		case "y":
			if len(m.rows) > 0 {
				m.status = copyCommand(m.rows[m.sel].ResumeCmd)
			}
		}
	}
	return m, nil
}
func trimLast(s string) string {
	r := []rune(s)
	if len(r) > 0 {
		return string(r[:len(r)-1])
	}
	return s
}
func (m *model) jump(next bool) {
	if len(m.rows) == 0 {
		return
	}
	hits := []int{}
	for i, x := range m.messages {
		if m.hitIndex[x.Index] {
			hits = append(hits, i)
		}
	}
	if len(hits) == 0 {
		return
	}
	at := -1
	for i, v := range hits {
		if v == m.cursor {
			at = i
		}
	}
	if next {
		m.cursor = hits[(at+1)%len(hits)]
	} else {
		m.cursor = hits[(at-1+len(hits))%len(hits)]
	}
}
func matches(text string, ts []term) bool {
	positive := false
	for _, t := range ts {
		yes := strings.Contains(strings.ToLower(text), strings.ToLower(t.Word))
		if t.Negative {
			if yes {
				return false
			}
		} else {
			positive = true
			if !yes {
				return false
			}
		}
	}
	return positive
}
func (m model) mouseUpdate(x tea.MouseMsg) (tea.Model, tea.Cmd) {
	if !m.mouse {
		return m, nil
	}
	if x.Action == tea.MouseActionPress && x.Button == tea.MouseButtonLeft {
		if x.Y == 0 {
			m.focus = true
			return m, nil
		}
		if x.Y == 1 {
			col := len("highlights ")
			for i, p := range m.pens {
				w := displayWidth(displayInline(p.word)) + 2
				if x.X >= col && x.X < col+w {
					m.pens = append(m.pens[:i], m.pens[i+1:]...)
					break
				}
				col += w + 1
			}
			return m, nil
		}
		top := 3
		listH := m.listHeight()
		if !m.full && x.Y >= top && x.Y < top+listH {
			i := m.offset + x.Y - top
			if i < len(m.rows) {
				m.sel = i
				m.focus = false
				return m, m.requestLoad()
			}
			m.focus = false
			return m, nil
		}
		m.focus = false
	}
	if x.Button == tea.MouseButtonWheelDown || x.Button == tea.MouseButtonWheelUp {
		step := 3
		if x.Button == tea.MouseButtonWheelUp {
			step = -3
		}
		if x.Y < 3+m.listHeight() && !m.full {
			m.offset = max(0, min(max(0, len(m.rows)-m.listHeight()), m.offset+step))
		} else {
			m.cursor = max(0, min(len(m.messages)-1, m.cursor+step))
		}
	}
	return m, nil
}
func (m model) listHeight() int {
	if m.full {
		return 0
	}
	return max(2, (m.height-5)*38/100)
}
func (m model) color(s, c string) string {
	return lipgloss.NewStyle().Foreground(lipgloss.Color(c)).Render(displayInline(s))
}
func (m model) dim(s string) string { return "\x1b[2m" + s + "\x1b[22m" }
func (m model) band(h string) string {
	switch h {
	case "claude":
		return m.pal.claude
	case "codex":
		return m.pal.codex
	default:
		return m.pal.pi
	}
}

// ANSI-aware grapheme width; ambiguous-width characters occupy one cell.
func displayWidth(s string) int { return ansi.StringWidth(s) }

func displayText(s string, multiline bool) string {
	s = ansi.Strip(strings.ReplaceAll(s, "\r\n", "\n"))
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\n' || r == '\r':
			if multiline {
				b.WriteByte('\n')
			} else {
				b.WriteByte(' ')
			}
		case r == '\t':
			if multiline {
				b.WriteString("    ")
			} else {
				b.WriteByte(' ')
			}
		case unicode.IsControl(r) || unicode.Is(unicode.Cf, r) && r != '\u200c' && r != '\u200d':
			// Escape and bidi controls must not steer the terminal or reorder text.
		case unicode.IsSpace(r):
			b.WriteByte(' ')
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
func displayInline(s string) string     { return displayText(s, false) }
func displayTranscript(s string) string { return displayText(s, true) }

func pad(s string, n int) string {
	w := displayWidth(s)
	if w >= n {
		return s
	}
	return s + strings.Repeat(" ", n-w)
}
func clip(s string, n int) string {
	if n <= 0 {
		return ""
	}
	if displayWidth(s) <= n {
		return s
	}
	g := uniseg.NewGraphemes(s)
	end, cells := 0, 0
	for g.Next() {
		if cells+displayWidth(g.Str()) > n-1 {
			break
		}
		_, end = g.Positions()
		cells += displayWidth(g.Str())
	}
	prefix := s[:end]
	if end < len(s) {
		next, _ := utf8.DecodeRuneInString(s[end:])
		lastPart := prefix
		last, size := utf8.DecodeLastRuneInString(lastPart)
		for unicode.Is(unicode.Mn, last) && size > 0 {
			lastPart = lastPart[:len(lastPart)-size]
			last, size = utf8.DecodeLastRuneInString(lastPart)
		}
		if latinWord(last) && latinWord(next) {
			for len(prefix) > 0 {
				r, size := utf8.DecodeLastRuneInString(prefix)
				if !latinWord(r) && !unicode.Is(unicode.Mn, r) {
					break
				}
				prefix = prefix[:len(prefix)-size]
			}
		}
	}
	return strings.TrimRightFunc(prefix, unicode.IsSpace) + "…"
}
func latinWord(r rune) bool { return unicode.Is(unicode.Latin, r) || unicode.IsDigit(r) || r == '_' }
func (m model) paint(s string, query bool) string {
	ts := terms(m.q)
	r := []rune(s)
	h := make([]bool, len(r))
	marks := make([]int, len(r))
	for i := range marks {
		marks[i] = -1
	}
	for _, p := range m.pens {
		for _, at := range positions(r, p.word) {
			for j := at; j < len(r) && j < at+len([]rune(p.word)); j++ {
				marks[j] = p.color
			}
		}
	}
	if query {
		for _, t := range ts {
			if t.Negative {
				continue
			}
			for _, at := range positions(r, t.Word) {
				for j := at; j < len(r) && j < at+len([]rune(t.Word)); j++ {
					h[j] = true
				}
			}
		}
	}
	var b strings.Builder
	for i := 0; i < len(r); {
		j := i + 1
		for j < len(r) && h[j] == h[i] && marks[j] == marks[i] {
			j++
		}
		s := string(r[i:j])
		if h[i] || marks[i] >= 0 {
			style := lipgloss.NewStyle()
			if h[i] {
				style = style.Foreground(lipgloss.Color(m.pal.hit)).Underline(true).Bold(true)
			}
			if marks[i] >= 0 {
				style = style.Background(lipgloss.Color(m.pal.pens[marks[i]]))
			}
			s = style.Render(s)
		}
		b.WriteString(s)
		i = j
	}
	return b.String()
}
func fold(s string) string {
	var b strings.Builder
	for _, r := range norm.NFD.String(strings.ToLower(s)) {
		if !unicode.Is(unicode.Mn, r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}
func positions(r []rune, word string) []int {
	w := []rune(strings.ToLower(word))
	if len(w) == 0 {
		return nil
	}
	var out []int
	for i := 0; i+len(w) <= len(r); i++ {
		if fold(string(r[i:i+len(w)])) == fold(word) {
			if isCJK(w[0]) || i == 0 || (!unicode.IsLetter(r[i-1]) && !unicode.IsDigit(r[i-1])) {
				out = append(out, i)
			}
		}
	}
	return out
}
func (m model) View() string {
	if m.width < 25 || m.height < 10 {
		return fitLine("hindsight · enlarge terminal", max(0, m.width))
	}
	w := m.width
	var b strings.Builder
	count := ""
	if m.progress != "" {
		count = m.progress
	} else if toFTS(m.q) == "" {
		count = fmt.Sprintf("%d recent sessions", len(m.rows))
	} else {
		sessions := map[string]bool{}
		for _, r := range m.rows {
			sessions[r.UID] = true
		}
		count = fmt.Sprintf("%d messages · %d sessions", len(m.rows), len(sessions))
	}
	q := m.color("hindsight", m.pal.ink) + " " + m.color("▸", m.pal.muted) + " "
	input := displayInline(m.q)
	if m.focus {
		input += "▌"
	}
	right := m.color(count, m.pal.muted)
	line := q + pad(clip(input, max(1, w-displayWidth(q)-displayWidth(right)-2)), max(1, w-displayWidth(q)-displayWidth(right))) + right
	if !m.focus {
		line = m.dim(line)
	}
	b.WriteString(line + "\n")
	ps := m.color("highlights ", m.pal.muted)
	if len(m.pens) == 0 {
		ps += m.color("none · press h in results to add", m.pal.muted)
	}
	for _, p := range m.pens {
		ps += lipgloss.NewStyle().Background(lipgloss.Color(m.pal.pens[p.color])).Render(" "+displayInline(p.word)+" ") + " "
	}
	ps = clipANSI(ps, w)
	if !m.focus {
		ps = m.dim(ps)
	}
	b.WriteString(ps + "\n")
	rule := m.color(strings.Repeat("─", w), m.pal.rule)
	b.WriteString(rule + "\n")
	listH := m.listHeight()
	if !m.full {
		for i := 0; i < listH; i++ {
			idx := m.offset + i
			if idx >= len(m.rows) {
				if idx == 0 {
					b.WriteString(m.color(" No message contains all of these words. Drop a word or remove the quotes.", m.pal.muted))
				}
				b.WriteString("\n")
				continue
			}
			x := m.rows[idx]
			agW := 8
			pjW := 12
			ageW := 7
			sw := max(5, w-agW-pjW-ageW-3)
			sn := clip(displayInline(x.Snippet), sw)
			row := m.color("▌", m.band(x.Harness)) + " " + pad(m.paint(sn, true), sw) + " " + pad(m.color(x.Harness, m.band(x.Harness)), agW) + pad(m.color(clip(displayInline(x.Project), pjW-1), m.pal.muted), pjW) + m.color(fmt.Sprintf("%*s", ageW, age(x.TS)), m.pal.muted)
			if idx == m.sel {
				row = lipgloss.NewStyle().Background(lipgloss.Color(m.pal.selbg)).Render(row)
			}
			row = clipANSI(row, w)
			if m.focus {
				row = m.dim(row)
			}
			b.WriteString(row + "\n")
		}
		b.WriteString(rule + "\n")
	}
	extra := 0
	if m.status != "" && !m.prompt {
		extra = 1
	}
	pageH := max(1, m.height-6-listH-extra)
	if m.full {
		pageH = max(1, m.height-5-extra)
	}
	lines := m.pageLines(w)
	for i := 0; i < pageH; i++ {
		if i < len(lines) {
			if m.focus {
				b.WriteString(m.dim(lines[i]))
			} else {
				b.WriteString(lines[i])
			}
		}
		b.WriteByte('\n')
	}
	b.WriteString(rule + "\n")
	if m.prompt {
		b.WriteString(m.color("highlight ▸ ", m.pal.ink) + displayInline(m.status) + "▌  enter add · esc cancel")
	} else if m.help {
		b.WriteString("focus · query · ↑↓ · n/N · h/H · v · o · y · enter · tab · ctrl+c")
	} else {
		if m.status != "" {
			b.WriteString(m.color(clip(displayInline(m.status), w), m.pal.ink) + "\n")
		}
		if m.focus {
			b.WriteString(m.color("type to search   ↓/esc results   enter resume   tab agent", m.pal.muted))
		} else {
			label, _ := editor()
			b.WriteString(m.color(clip("↑↓ move  n/N next hit  h highlight  H clear  v full  o open in "+label+"  y copy  enter resume  / search  ?", w), m.pal.muted))
		}
	}
	rendered := strings.Split(b.String(), "\n")
	for i := range rendered {
		rendered[i] = fitLine(rendered[i], w)
	}
	return strings.Join(rendered, "\n")
}
func clipANSI(s string, w int) string {
	if w <= 0 {
		return ""
	}
	plain := ansi.Strip(s)
	short := clip(plain, w)
	if plain == short {
		return s
	}
	return ansi.Truncate(s, displayWidth(strings.TrimSuffix(short, "…"))+1, "…") + "\x1b[0m"
}
func fitLine(s string, w int) string {
	s = clipANSI(s, w)
	return s + strings.Repeat(" ", max(0, w-displayWidth(s)))
}
func (m model) pageLines(w int) []string {
	if m.help {
		return []string{"  focus    Bright zone takes keys; search dims results", "  query    space = AND · quotes = phrase · -word = exclude", "  ↓ / esc search to results    / results to search", "  ↑ ↓     previous / next message", "  n / N   next / previous hit in transcript", "  h / H   add highlighter / clear highlights", "  v       full transcript (hide hit list)", "  o       open directory in editor", "  y       copy resume command", "  enter   exit and resume in original cwd", "  tab     all · claude · codex · pi", "  ctrl+c  quit"}
	}
	if len(m.rows) == 0 {
		return nil
	}
	sel := m.rows[m.sel]
	header := "     " + m.color(sel.Project, m.pal.ink) + "  " + m.color(sel.CWD+"  "+sel.TS[:min(10, len(sel.TS))], m.pal.muted) + "  " + m.color(sel.Harness, m.band(sel.Harness))
	out := []string{clipANSI(header, w)}
	keep := map[int]bool{}
	active := toFTS(m.q) != ""
	start, end := 0, len(m.messages)
	// ponytail: render a 200-message window for huge sessions; virtualize line offsets if direct arbitrary scrolling is needed.
	if end > 200 {
		start = max(0, m.cursor-100)
		end = min(end, start+200)
	}
	for i := start; i < end; i++ {
		x := m.messages[i]
		if m.full || !active || m.hitIndex[x.Index] {
			keep[i] = true
			if !m.full && active {
				for j := i; j >= start; j-- {
					if m.messages[j].Role == "user" {
						keep[j] = true
						break
					}
				}
			}
		}
	}
	prev := -1
	folded := start > 0
	for i := start; i < end; i++ {
		x := m.messages[i]
		if !keep[i] {
			folded = true
			continue
		}
		if prev >= 0 && (folded || gap(m.messages[prev].TS, x.TS)) {
			out = append(out, m.color("     ⋯", m.pal.muted))
		}
		folded = false
		if x.Role == "user" && prev >= 0 {
			out = append(out, "")
		}
		who := clip(displayInline(x.Role), 5)
		if who == "user" {
			who = "you"
		}
		star := "  "
		if active && m.hitIndex[x.Index] {
			star = m.color("✱ ", m.pal.hit)
		}
		stamp := x.TS
		if len(stamp) >= 16 {
			stamp = stamp[11:16]
		}
		prefix := star + " " + m.color(fmt.Sprintf("%-5s", stamp), m.pal.muted) + " " + m.color(pad(who, 5), m.pal.muted) + " "
		if who == "you" {
			prefix = star + " " + m.color(fmt.Sprintf("%-5s", stamp), m.pal.muted) + " " + m.color(pad(who, 5), m.pal.ink) + " "
		}
		textW := max(5, w-15)
		for j, line := range wrap(displayTranscript(x.Text), textW) {
			p := prefix
			if j > 0 {
				p = strings.Repeat(" ", 15)
			}
			line = p + m.paint(line, active)
			if i == m.cursor {
				line = lipgloss.NewStyle().Background(lipgloss.Color(m.pal.selbg)).Render(line)
			}
			out = append(out, clipANSI(line, w))
		}
		prev = i
	}
	if folded || end < len(m.messages) {
		out = append(out, m.color("     ⋯", m.pal.muted))
	}
	extra := 0
	if m.status != "" && !m.prompt {
		extra = 1
	}
	available := max(1, m.height-6-m.listHeight()-extra)
	if m.full {
		available = max(1, m.height-5-extra)
	}
	if len(out) > available {
		focus := 0
		for i, l := range out {
			if strings.Contains(l, "\x1b[48;") {
				focus = i
				break
			}
		}
		start := max(0, min(len(out)-available, focus-available/2))
		out = out[start:]
	}
	return out
}
func gap(a, b string) bool {
	x, e := time.Parse(time.RFC3339Nano, a)
	y, f := time.Parse(time.RFC3339Nano, b)
	return e == nil && f == nil && y.Sub(x) >= time.Hour
}
func wrap(s string, w int) []string {
	var out []string
	for _, ln := range strings.Split(s, "\n") {
		if ln == "" {
			out = append(out, "")
			continue
		}
		for len(ln) > 0 {
			g := uniseg.NewGraphemes(ln)
			end, cells := 0, 0
			for g.Next() {
				v := displayWidth(g.Str())
				if cells+v > w {
					break
				}
				_, end = g.Positions()
				cells += v
			}
			if end == 0 {
				g = uniseg.NewGraphemes(ln)
				g.Next()
				_, end = g.Positions()
			}
			out = append(out, ln[:end])
			ln = ln[end:]
		}
	}
	return out
}
