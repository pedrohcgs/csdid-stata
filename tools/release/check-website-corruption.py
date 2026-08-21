#!/usr/bin/env python3
r"""Text on a public page that no author wrote.

A page can be damaged by a tool that edits at a character offset computed
against a version of the file it no longer has. What comes out still reads like
prose, so no gate that checks tables, numbers or provenance can see it: those
gates read the objects they own and none of them reads a sentence.

Six rules, each for a form of damage that HAS occurred on this site:

R1  SPLICE.  A parity fixture id -- f011, rt042, py020 -- wedged against a
    word: `refF011lect' for `reflect', `F011reflect' at the start of one,
    `reflectF011' at the end. A page may name a fixture id in a sentence of its
    own accord, so the damage is the ADJACENCY to a letter, on either side. The
    ids are read from tests/fixtures/parity/, not guessed from a shape, which
    is what keeps a git short hash out of it: `af123b' contains no fixture id
    at all, and a token that is entirely lowercase hex is exempt in any case.
    An earlier form of this rule required a letter on BOTH sides, so it saw
    only strictly-interior splices, and its shape rule turned red on hashes.

R2  CONFLICT MARKERS, every form: `<<<<<<<', `=======', `>>>>>>>' and the
    diff3 `|||||||'. The middle marker alone is the one that survives a
    careless resolution, and it was the one form the earlier rule did not
    look for.

R3  EATEN SPACE BEFORE EMPHASIS.  `adoption*order*' where the page should read
    `adoption *order*'. This renders as emphasis either way, so it is invisible
    on the published page; it reached a commit once and was repaired by hand.
    Code is exempt: `n*T' and `0.5*(time-gvar)' are multiplication.

R4  EATEN SPACE AROUND AN ESCAPED PIPE.  In a table cell, `P(G=g \| G+e)' has a
    space on both sides of the escaped pipe and `mammen\|gaussian' has one on
    neither. One side but not the other is a space that went missing.

R5  UNBALANCED DISPLAY MATH.  `$$' delimiters come in pairs. An odd count is a
    page carrying an orphan -- one was appended at end of file.

R6  WHOLESALE REFORMAT.  The damage that recurs is not a splice but a rewrite:
    inline `$$x$$' exploded onto standalone lines, `&mdash;' entities collapsed
    from 46 to 12, spaces eaten throughout. Individually each of those is a
    legal edit; together they are a page nobody edited. What makes it
    detectable is that the counts move WHOLESALE, so tools/release/
    website-shape.json records them per page and this rule reports a move of at
    least six that is also at least a quarter of the recorded count. Ordinary
    authoring does not move them that far; when it genuinely does, rerun with
    --update, which prints every move before it accepts it.

Usage:
  python3 tools/release/check-website-corruption.py [site-root]
  python3 tools/release/check-website-corruption.py [site-root] --update

Exit 0 on success; print every hit with file, line and rule, and exit 1.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

FIXTURE_DIR = os.path.join(ROOT, "tests", "fixtures", "parity")
LEDGER = os.path.join(HERE, "website-shape.json")

FIXTURE_ID = re.compile(r"^(?:f|rt|py)\d{3}$")

FENCE = re.compile(r"^\s*(?:```|~~~)")
PRE_OPEN = re.compile(r"<pre\b")
PRE_CLOSE = re.compile(r"</pre>")
INLINE_CODE = re.compile(r"`[^`]*`")

CONFLICT = re.compile(r"^(?:<{7}|={7}|>{7}|\|{7})(?:\s|$)")
GLUED_EMPHASIS = re.compile(r"[0-9A-Za-z]\*[A-Za-z]")
LOPSIDED_PIPE = re.compile(r"(?:\S\\\| |\s\\\|\S)")
HEXISH = re.compile(r"^[0-9a-f]{6,40}$")
TOKEN = re.compile(r"[0-9A-Za-z]+")

# R6 fires only when a count moves by at least this much AND by at least this
# share of what was recorded. Both, so that a page with a large count is not
# tripped by ordinary editing and a page with a small one is not tripped by a
# single character.
SHAPE_MIN_MOVE = 6
SHAPE_MIN_SHARE = 0.25


def fixture_ids():
    """Every parity fixture id in the tree, lowercased."""
    if not os.path.isdir(FIXTURE_DIR):
        return []
    return sorted(d for d in os.listdir(FIXTURE_DIR)
                  if FIXTURE_ID.match(d)
                  and os.path.isdir(os.path.join(FIXTURE_DIR, d)))


def markdown_pages(site):
    for dirpath, dirnames, filenames in os.walk(site):
        dirnames[:] = [d for d in dirnames if d != "_site"]
        for name in sorted(filenames):
            if name.endswith(".md"):
                full = os.path.join(dirpath, name)
                yield os.path.relpath(full, site), full


def split_code(lines):
    """(prose, code) line lists, each of (lineno, text).

    Prose has inline code spans blanked out as well, because a backticked
    `n*T' is code wherever it appears.
    """
    prose, code = [], []
    in_fence = in_pre = False
    for n, line in enumerate(lines, 1):
        opening_pre = bool(PRE_OPEN.search(line))
        if in_fence or in_pre or opening_pre:
            code.append((n, line))
        else:
            prose.append((n, INLINE_CODE.sub("", line)))
        if FENCE.match(line):
            in_fence = not in_fence
        if opening_pre:
            in_pre = True
        if PRE_CLOSE.search(line):
            in_pre = False
    return prose, code


def splices(lines, ids):
    """R1: a fixture id sitting against a letter."""
    hits = []
    for n, line in lines:
        low = line.lower()
        for fid in ids:
            start = 0
            while True:
                i = low.find(fid, start)
                if i < 0:
                    break
                start = i + 1
                j = i + len(fid)
                before = line[i - 1] if i > 0 else ""
                after = line[j] if j < len(line) else ""
                if not (before.isalpha() or after.isalpha()):
                    continue
                token = TOKEN.search(line, max(0, i - 40))
                while token and token.end() <= i:
                    token = TOKEN.search(line, token.end())
                if token and HEXISH.match(token.group(0)):
                    continue
                hits.append((n, "splice",
                             "the fixture id %s is wedged against a word: %r"
                             % (fid, (token.group(0) if token
                                      else line[max(0, i - 8):j + 8]))))
    return hits


def shape_of(text):
    lines = text.splitlines()
    return {
        "mdash": text.count("&mdash;"),
        "dollar_lines": sum(1 for l in lines if l.strip() == "$$"),
        "dollars": text.count("$$"),
    }


def shape_moves(recorded, current):
    """Which recorded counts moved wholesale."""
    moves = []
    for key in sorted(current):
        was = recorded.get(key, 0)
        now = current[key]
        delta = abs(now - was)
        if delta >= SHAPE_MIN_MOVE and delta >= SHAPE_MIN_SHARE * max(was, 1):
            moves.append((key, was, now))
    return moves


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    update = "--update" in argv[1:]
    site = args[0] if args else os.path.join(ROOT, "website")
    if not os.path.isdir(site):
        print("no such directory: %s" % site, file=sys.stderr)
        return 2

    ids = fixture_ids()
    if not ids:
        print("FAIL: no parity fixture ids found under %s -- the splice rule "
              "has nothing to look for" % os.path.relpath(FIXTURE_DIR, ROOT),
              file=sys.stderr)
        return 1

    recorded = {}
    if os.path.isfile(LEDGER):
        with open(LEDGER, encoding="utf-8") as fh:
            recorded = json.load(fh)
    elif not update:
        print("FAIL: %s is missing; the reformat rule has nothing to compare "
              "against. Rerun with --update to record the current shapes"
              % os.path.relpath(LEDGER, ROOT), file=sys.stderr)
        return 1

    problems = []
    fresh = {}
    scanned = 0
    for rel, full in markdown_pages(site):
        with open(full, encoding="utf-8") as fh:
            text = fh.read()
        lines = text.splitlines()
        prose, _ = split_code(lines)
        scanned += 1

        hits = []
        hits += splices(list(enumerate(lines, 1)), ids)                  # R1
        for n, line in enumerate(lines, 1):                              # R2
            if CONFLICT.match(line):
                hits.append((n, "conflict-marker",
                             "a merge conflict marker: %r" % line[:16]))
        for n, line in prose:                                            # R3
            m = GLUED_EMPHASIS.search(line)
            if m:
                hits.append((n, "eaten-space",
                             "emphasis with no space in front of it: %r"
                             % line[max(0, m.start() - 12):m.end() + 12]))
            m = LOPSIDED_PIPE.search(line)                               # R4
            if m:
                hits.append((n, "eaten-space",
                             "an escaped pipe spaced on one side only: %r"
                             % line[max(0, m.start() - 12):m.end() + 12]))
        prose_text = "\n".join(l for _, l in prose)
        if prose_text.count("$$") % 2:                                   # R5
            hits.append((0, "unbalanced-math",
                         "an odd number of $$ delimiters (%d); one is an "
                         "orphan" % prose_text.count("$$")))

        current = shape_of(text)                                         # R6
        fresh[rel] = current
        if rel in recorded:
            for key, was, now in shape_moves(recorded[rel], current):
                hits.append((0, "reformat",
                             "%s went from %d to %d; a count that moves that "
                             "far without the page being rewritten is a "
                             "reformat, not an edit" % (key, was, now)))
        elif not update:
            hits.append((0, "reformat",
                         "this page has no recorded shape; register it with "
                         "--update so a later rewrite can be seen"))

        for n, rule, why in sorted(hits):
            where = "%s:%d" % (rel, n) if n else rel
            problems.append("%s [%s] %s" % (where, rule, why))

    for rel in sorted(set(recorded) - set(fresh)):
        if not update:
            problems.append("%s [reformat] has a recorded shape but is no "
                            "longer on the site; drop it with --update" % rel)

    if not scanned:
        problems.append("scanned no markdown under %s -- this gate is checking "
                        "nothing" % site)

    if update:
        for rel in sorted(fresh):
            for key, was, now in shape_moves(recorded.get(rel, {}), fresh[rel]):
                print("   %s: %s %d -> %d" % (rel, key, was, now))
        with open(LEDGER, "w", encoding="utf-8") as fh:
            json.dump(fresh, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print("recorded the shape of %d pages in %s"
              % (len(fresh), os.path.relpath(LEDGER, ROOT)))
        return 0

    if problems:
        for p in problems:
            print("FAIL: %s" % p, file=sys.stderr)
        print("\nA published page is carrying text no author wrote.\nRestore "
              "the page from its committed version; do not patch the symptom.",
              file=sys.stderr)
        return 1

    print("website corruption ok (%d pages, %d fixture ids)"
          % (scanned, len(ids)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
