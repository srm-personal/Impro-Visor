#!/usr/bin/env python3
"""Build goldens/cases.tsv — the tune x style x seed matrix — deterministically
from goldens/parse/leadsheet-counts.tsv. No randomness: selection is by sorted
order within coverage buckets, so re-running gives the same file.

  matrix  50 tunes x 10 styles (one per style family)          500 cases
  styles  every shipped style on one blues and one 3/4 tune     290 cases
  own     the 50 tunes with their own styles/sections            50 cases
  seeds   5 tunes x 3 extra seeds in their own style             15 cases
  interp  50 tunes x the 2 interpolating/substituting styles   100 cases
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TESTING = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TESTING))
rows = []
for line in open(os.path.join(TESTING, "goldens/parse/leadsheet-counts.tsv")):
    if line.startswith("#"):
        continue
    f = line.rstrip("\n").split("\t")
    if f[1] != "ok":
        continue
    rows.append(dict(path=f[0], metre=f[2], tempo=float(f[3]), key=int(f[4]),
                     slots=int(f[5]), chords=int(f[6]), sections=int(f[7]),
                     parts=int(f[8]), first=f[10], msgs=f[11]))

def bars(r):
    n, d = map(int, r["metre"].split("/"))
    return r["slots"] / (n * 480 // d)

def ok(r):
    # Keep goldens small and meaningful: real progressions, at most 64 bars,
    # no parse warnings.
    return 8 <= bars(r) <= 64 and r["chords"] >= 8 and r["msgs"].startswith("0")

def complexity(r):
    text = open(os.path.join(REPO, r["path"]), encoding="latin-1").read()
    return (("/" in r["first"]), ("\\" in text), len(set(re.findall(r"[A-G][b#]?[^ |/\s]*", r["first"]))))

book = sorted([r for r in rows if r["path"].startswith("leadsheets/imaginary-book/") and ok(r)],
              key=lambda r: r["path"])
tunes, seen = [], set()

def take(candidates, n):
    got = 0
    for r in candidates:
        if got >= n:
            break
        if r["path"] not in seen:
            seen.add(r["path"]); tunes.append(r); got += 1

# Meters: every meter in the book, 3/4 best represented after 4/4.
for metre, n in [("3/4", 6), ("6/8", 2), ("5/4", 2), ("2/4", 1), ("12/8", 1), ("6/4", 1), ("7/4", 1), ("2/2", 1)]:
    take([r for r in sorted(rows, key=lambda r: r["path"]) if r["metre"] == metre and ok(r)], n)
four = [r for r in book if r["metre"] == "4/4"]
# Keys: one tune for each key signature -6 … +6.
for k in range(-6, 7):
    take([r for r in four if r["key"] == k], 1)
# Tempos: slow, medium, fast, very fast.
for lo, hi in [(0, 80), (80, 120), (200, 260), (260, 1000)]:
    take([r for r in four if lo <= r["tempo"] < hi], 2)
# Sections: multi-section tunes and section style changes.
take(sorted([r for r in four if r["sections"] >= 4], key=lambda r: (-r["sections"], r["path"])), 4)
# Chord-symbol complexity: slash chords, many chords per bar, very sparse.
take([r for r in four if "/" in re.sub(r"/\d+", "", r["first"])], 3)
take(sorted(four, key=lambda r: (-r["chords"] / bars(r), r["path"])), 3)
take(sorted(four, key=lambda r: (r["chords"] / bars(r), r["path"])), 2)
# Fill to 50 with evenly spaced tunes from the rest of the book.
rest = [r for r in four if r["path"] not in seen]
need = 50 - len(tunes)
step = max(1, len(rest) // need)
take(rest[::step], need)
tunes = tunes[:50]
assert len(tunes) == 50, len(tunes)

# One style per family.
FAMILY = ["swing", "ballad", "bossa", "latin", "samba", "rock-medium", "funk",
          "waltz", "shuffle", "two-beat"]
styles = sorted(f[:-4] for f in os.listdir(os.path.join(REPO, "styles")) if f.endswith(".sty"))
for s in FAMILY:
    assert s in styles, s

def slug(path):
    return re.sub(r"[^A-Za-z0-9]+", "_", os.path.splitext(os.path.basename(path))[0]).strip("_")

cases = []
for i, t in enumerate(tunes):
    for s in FAMILY:
        cases.append((f"m{i:02d}_{slug(t['path'])}__{s}", t["path"], s, 1000 + i))
blues = "leadsheets/imaginary-book/12-barBlues.ls"
waltz = next(t["path"] for t in tunes if t["metre"] == "3/4")
for s in styles:
    cases.append((f"s_blues__{s}", blues, s, 7))
    cases.append((f"s_waltz__{s}", waltz, s, 7))
for i, t in enumerate(tunes):
    cases.append((f"o{i:02d}_{slug(t['path'])}", t["path"], "-", 2000 + i))
for i, t in enumerate(tunes[:50:10]):
    for seed in (1, 42, 123456789):
        cases.append((f"x{i:02d}_{slug(t['path'])}__seed{seed}", t["path"], "-", seed))

# Passing-chord interpolation and substitution rewrite the progression, so
# give the two styles that use them every tune rather than only two.
for i, t in enumerate(tunes):
    for s in ("swing-interpolate", "swing-substitute"):
        cases.append((f"i{i:02d}_{slug(t['path'])}__{s}", t["path"], s, 3000 + i))

ids = [c[0] for c in cases]
assert len(ids) == len(set(ids)), "duplicate case ids"
with open(os.path.join(TESTING, "goldens/cases.tsv"), "w") as out:
    out.write("# id\tleadsheet\tstyle (- = the leadsheet's own)\tseed\n")
    for c in cases:
        out.write("\t".join(map(str, c)) + "\n")
with open(os.path.join(TESTING, "goldens/tunes.tsv"), "w") as out:
    out.write("# the 50 matrix tunes and why they cover the space\n# path\tmetre\ttempo\tkey\tbars\tchords\tsections\n")
    for t in tunes:
        out.write(f"{t['path']}\t{t['metre']}\t{t['tempo']}\t{t['key']}\t{bars(t):g}\t{t['chords']}\t{t['sections']}\n")
print(f"{len(cases)} cases, {len(tunes)} tunes, {len(styles)} styles")
