# oklch -> sRGB hex + WCAG contrast against reference terminal grounds.
import math, json
def oklch_hex(L, C, h):
    a, b = C*math.cos(math.radians(h)), C*math.sin(math.radians(h))
    l_ = L + 0.3963377774*a + 0.2158037573*b
    m_ = L - 0.1055613458*a - 0.0638541728*b
    s_ = L - 0.0894841775*a - 1.2914855480*b
    l, m, s = l_**3, m_**3, s_**3
    rgb = [4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
           -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
           -0.0041960863*l - 0.7034186147*m + 1.7076147010*s]
    out = []
    for c in rgb:
        c = min(max(c, 0), 1)
        c = 12.92*c if c <= 0.0031308 else 1.055*c**(1/2.4) - 0.055
        out.append(round(c*255))
    return "#%02x%02x%02x" % tuple(out)
def lum(hx):
    v = [int(hx[i:i+2], 16)/255 for i in (1, 3, 5)]
    v = [c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4 for c in v]
    return 0.2126*v[0] + 0.7152*v[1] + 0.0722*v[2]
def cr(a, b):
    x, y = sorted([lum(a), lum(b)], reverse=True)
    return round((x+0.05)/(y+0.05), 2)
GROUND = {"light": "#ffffff", "dark": "#1c1d22"}
# role: (L, C, h) per theme; kind text needs 4.5, ui needs 3
P = {
 "log": {
  "ink":      ("text", (0.36, 0.08, 255), (0.86, 0.04, 255)),
  "hit":      ("text", (0.52, 0.17, 27),  (0.74, 0.14, 27)),
  "muted":    ("text", (0.52, 0.02, 250), (0.70, 0.02, 250)),
  "rule":     ("ui",   (0.62, 0.03, 250), (0.585, 0.03, 250)),
  "claude":   ("text", (0.52, 0.10, 70),  (0.78, 0.10, 75)),
  "codex":    ("text", (0.50, 0.08, 200), (0.78, 0.08, 200)),
  "pi":       ("text", (0.50, 0.10, 145), (0.78, 0.10, 145)),
  "selbg":    ("bg",   (0.955, 0.015, 255), (0.27, 0.02, 255)),
 },
 "kwic": {
  "key":      ("text", (0.46, 0.20, 275), (0.76, 0.13, 275)),
  "context":  ("text", (0.40, 0.01, 275), (0.82, 0.01, 275)),
  "muted":    ("text", (0.54, 0.015, 275), (0.66, 0.015, 275)),
  "rule":     ("ui",   (0.62, 0.01, 275), (0.585, 0.01, 275)),
  "claude":   ("text", (0.52, 0.09, 60),  (0.76, 0.09, 60)),
  "codex":    ("text", (0.50, 0.08, 220), (0.76, 0.08, 220)),
  "pi":       ("text", (0.50, 0.09, 150), (0.76, 0.09, 150)),
  "selbg":    ("bg",   (0.955, 0.02, 275), (0.28, 0.03, 275)),
 },
 "edge": {
  "text":     ("text", (0.36, 0.0, 0),    (0.86, 0.0, 0)),
  "muted":    ("text", (0.54, 0.0, 0),    (0.66, 0.0, 0)),
  "claude":   ("ui",   (0.62, 0.11, 170), (0.80, 0.10, 170)),
  "codex":    ("ui",   (0.62, 0.13, 0),   (0.78, 0.10, 0)),
  "pi":       ("ui",   (0.58, 0.15, 295), (0.76, 0.11, 295)),
  "hitmark":  ("text", (0.45, 0.0, 0),    (0.95, 0.0, 0)),
  "selbg":    ("bg",   (0.96, 0.0, 0),    (0.27, 0.0, 0)),
 },
}
res = {}
for d, roles in P.items():
    res[d] = {}
    for role, (kind, lt, dk) in roles.items():
        row = {"kind": kind}
        for theme, spec in (("light", lt), ("dark", dk)):
            hx = oklch_hex(*spec)
            row[theme] = {"hex": hx, "oklch": "oklch(%.3f %.3f %d)" % spec}
            if kind != "bg":
                g = GROUND[theme]
                row[theme]["cr"] = cr(hx, g)
                need = 4.5 if kind == "text" else 3
                row[theme]["pass"] = row[theme]["cr"] >= need
        res[d][role] = row
    # hit text must also hold on selected-row bg
    for key in ("hit", "key", "hitmark"):
        if key in roles:
            for theme in ("light", "dark"):
                res[d][key][theme]["cr_on_sel"] = cr(res[d][key][theme]["hex"], res[d]["selbg"][theme]["hex"])
json.dump({"ground": GROUND, "palettes": res}, open(".impeccable/palettes.json", "w"), indent=1, ensure_ascii=False)
for d in res:
    for r, v in res[d].items():
        print(d, r.ljust(8), *[f'{t}:{v[t]["hex"]} {v[t].get("cr","")}{"" if v[t].get("pass",True) else " FAIL"} {v[t].get("cr_on_sel","")}' for t in ("light","dark")])
