#!/usr/bin/env python3
"""NEWS.md and the shipped help must name the SAME sample for the same refusal.

Both files ship: NEWS.md is a root file in the release payload and
`csdid.sthlp' is installed by net install, so a user reads them side by side.
They are written in different voices and edited at different times, which is
how they came apart: the help said the panel-shape checks are judged on the
data as `if' and `in' leave it, before any row is set aside for carrying a
missing value, while NEWS still said they are judged on the estimation sample.
Both sentences read fluently. Only one of them is true, and no other gate
compares the two files at all -- check-help-surface.py reads the help alone,
and nothing reads NEWS.

WHICH SAMPLE a refusal is judged on is the one class of claim in these files
that is mechanically comparable: the surfaces describe a small, closed set of
stages, and two of those stages are mutually exclusive descriptions of the same
moment. So the check is not "do these paragraphs say the same thing" -- it is
"do these paragraphs name the same stages".

Five rules:

R1  For every registered claim below, the set of SAMPLE STAGES named in NEWS
    must equal the set named in the help. An empty set on either side is also a
    failure: a surface that stopped saying which sample it means has stopped
    being cross-checkable, and this gate would then be passing on silence.

R2  `the estimation sample' and `the data as if and in leave it' are mutually
    exclusive. A section that names both contradicts itself, whatever the other
    file says.

R3  src/help/csdid.sthlp and pkg/csdid.sthlp must be byte-identical. This gate
    reads the SHIPPED copy, because that is what the user has; if the two ever
    drift, a green run here would say nothing about the source the next build
    compiles.

R4  Every anchor must be found in both files. Anchor-based checks fail silently
    when a heading is reworded, so a missing anchor is a failure and not a skip.

R5  THE BOOTSTRAP REPLICATION DEFAULT, in all three places that state it:
    NEWS.md, the shipped help, and `src/ado/csdid.ado', which is the only one
    of the three that decides anything. This is not a wording question. The
    number is what a user has to type to reproduce someone else's standard
    errors, and NEWS said 999 in its performance section while its own
    compatibility table, the help and the ado all said 1,000. The ado is read
    ONLY -- nothing here edits it -- and the rule is equality: one value, in
    all three surfaces.

What this does NOT do is judge whether the agreed answer is the right one. The
source of truth is `src/ado/csdid.ado' -- the shape scan, the `mark' pass that
widens it back to the if/in sample, and the order of the two relative to the
balance block. When the code moves, both surfaces have to move with it, and
this gate only guarantees that they move together.

Run: python3 tools/release/check-news-help-agreement.py
Exit 0 on success; print every violation and exit 1.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

NEWS = os.path.join(ROOT, "NEWS.md")
SHIPPED_HELP = os.path.join(ROOT, "pkg", "csdid.sthlp")
SOURCE_HELP = os.path.join(ROOT, "src", "help", "csdid.sthlp")
CSDID_ADO = os.path.join(ROOT, "src", "ado", "csdid.ado")

# R5. Each surface states the bootstrap replication default in its own idiom,
# so each gets its own patterns; every number any of them matches is collected,
# and the three sets must be the same single value.
#
# In the ado, `local biters 0' is the not-bootstrapping value, set before the
# inference branch is entered and overwritten inside it -- it is a sentinel,
# not a default anyone can type, so it is dropped and any OTHER literal is
# kept. Two surviving values means the ado no longer has one default to
# compare against, and that is a failure rather than a guess.
BITERS_SENTINEL = "0"
ADO_DEFAULT = re.compile(r"^\s*local\s+biters\s+(\d+)\s*$", re.M)
HELP_DEFAULT = [
    re.compile(r"default is\s*\{cmd:reps\((\d+)\)\}", re.S),
]
NEWS_DEFAULT = [
    re.compile(r"([\d,]+)\s+is the default"),
    re.compile(r"default is\s*`?reps\((\d+)\)`?"),
    re.compile(r"default[^.]{0,120}?([\d,]+)\s+iterations"),
]

# The stages a refusal can be judged on, as the two surfaces spell them after
# markup is stripped. The first two are the pair that came apart; keeping them
# as separate labels is what makes R2 expressible.
STAGES = (
    ("estimation-sample",
     re.compile(r"judged on the estimation sample")),
    ("if-in-sample",
     re.compile(r"judged on the data as if and in leave it")),
    ("before-missing-screen",
     re.compile(r"before any row is set aside")),
    ("before-balance",
     re.compile(r"before bal\(full\)")),
    ("after-balance",
     re.compile(r"after (?:every reduction and after )?bal\(full\)")),
)

MUTUALLY_EXCLUSIVE = ("estimation-sample", "if-in-sample")

# One entry per claim the two files both make. `news' and `help' are the text
# that opens the section; the section runs to the next heading of the same
# kind. Both are matched after markup is stripped, so they are written the way
# the sentence reads rather than the way it is marked up.
CLAIMS = (
    {
        "key": "panel-shape-refusals",
        "what": "the duplicate-row, cohort-reversal and moving-cluster refusals",
        "news": "A panel that is not shaped like a panel is refused",
        "help": "Panel structure.",
    },
)

NEWS_HEADING = re.compile(r"^(?:#{2,4} |\*\*[A-Z])")
HELP_HEADING = re.compile(r"^(?:\{bf:|\{title:)")


def strip_markup(line):
    """Reduce a NEWS or SMCL line to the sentence a reader hears."""
    line = re.sub(r"\{(?:cmd|it|bf|opt|help [^:}]*):([^}]*)\}", r"\1", line)
    line = re.sub(r"\{[^}]*\}", "", line)
    line = line.replace("`", "").replace("*", "")
    line = line.replace("—", "--").replace("’", "'")
    return line


def section(path, opener, heading):
    """The lines from the line containing `opener' to the next heading."""
    with open(path, encoding="utf-8") as fh:
        raw = fh.read().splitlines()
    plain = [strip_markup(l) for l in raw]
    start = None
    for n, line in enumerate(plain):
        if opener in line:
            start = n
            break
    if start is None:
        return None
    end = len(plain)
    for n in range(start + 1, len(plain)):
        if heading.match(raw[n]) and opener not in plain[n]:
            end = n
            break
    return " ".join(plain[start:end])


def stages_in(text):
    return {name for name, pattern in STAGES if pattern.search(text)}


def numbers(text, patterns):
    """Every replication count `patterns' finds, commas removed."""
    found = set()
    for pattern in patterns:
        for hit in pattern.findall(text):
            found.add(hit.replace(",", ""))
    return found


def check_bootstrap_default(problems):
    """R5: NEWS, the shipped help and the ado must state one same default."""
    with open(CSDID_ADO, encoding="utf-8") as fh:
        ado_text = fh.read()
    with open(SHIPPED_HELP, encoding="utf-8") as fh:
        help_text = fh.read()
    with open(NEWS, encoding="utf-8") as fh:
        news_text = fh.read()

    ado = {v for v in ADO_DEFAULT.findall(ado_text) if v != BITERS_SENTINEL}
    helped = numbers(help_text, HELP_DEFAULT)
    newsed = numbers(news_text, NEWS_DEFAULT)

    for where, found, how in (("src/ado/csdid.ado", ado, "`local biters #'"),
                              ("pkg/csdid.sthlp", helped, "`default is reps(#)'"),
                              ("NEWS.md", newsed, "a stated default")):
        if not found:
            problems.append(
                "bootstrap-default: %s states no bootstrap replication default "
                "that this gate can read (%s); a surface that stopped saying it "
                "cannot be cross-checked, and this rule would be passing on "
                "silence" % (where, how))
    if not (ado and helped and newsed):
        return 0
    if len(ado) > 1:
        problems.append(
            "bootstrap-default: src/ado/csdid.ado sets `local biters' to more "
            "than one literal value (%s), so it no longer has a single default "
            "to compare the surfaces against"
            % ", ".join(sorted(ado)))
        return 0
    if len(helped) > 1 or len(newsed) > 1 or ado != helped or ado != newsed:
        problems.append(
            "bootstrap-default: the three surfaces do not agree on the number "
            "of bootstrap replications csdid runs by default. "
            "src/ado/csdid.ado: %s. pkg/csdid.sthlp: %s. NEWS.md: %s. The ado "
            "decides; the other two describe it, and a reader who trusts the "
            "wrong one cannot reproduce a standard error"
            % (", ".join(sorted(ado)), ", ".join(sorted(helped)),
               ", ".join(sorted(newsed))))
        return 0
    return 1


def main():
    problems = []

    # R3 first: everything below reads the shipped copy.
    with open(SHIPPED_HELP, "rb") as fh:
        shipped = fh.read()
    with open(SOURCE_HELP, "rb") as fh:
        source = fh.read()
    if shipped != source:
        problems.append(
            "pkg/csdid.sthlp and src/help/csdid.sthlp differ; this gate reads "
            "the shipped copy, so it would say nothing about the source. "
            "Rerun src/build.do")

    checked = 0
    for claim in CLAIMS:
        news_text = section(NEWS, claim["news"], NEWS_HEADING)
        help_text = section(SHIPPED_HELP, claim["help"], HELP_HEADING)
        # R4
        if news_text is None:
            problems.append(
                "%s: NEWS.md no longer contains the anchor %r; the claim is "
                "unchecked until the anchor is updated"
                % (claim["key"], claim["news"]))
        if help_text is None:
            problems.append(
                "%s: pkg/csdid.sthlp no longer contains the anchor %r; the "
                "claim is unchecked until the anchor is updated"
                % (claim["key"], claim["help"]))
        if news_text is None or help_text is None:
            continue
        checked += 1

        news_stages = stages_in(news_text)
        help_stages = stages_in(help_text)

        # R2
        for text, where, found in ((news_text, "NEWS.md", news_stages),
                                   (help_text, "pkg/csdid.sthlp", help_stages)):
            if set(MUTUALLY_EXCLUSIVE) <= found:
                problems.append(
                    "%s: %s says both %s and %s of %s; those are two different "
                    "samples" % (claim["key"], where, MUTUALLY_EXCLUSIVE[0],
                                 MUTUALLY_EXCLUSIVE[1], claim["what"]))

        # R1
        if not news_stages or not help_stages:
            problems.append(
                "%s: NEWS.md names %s and pkg/csdid.sthlp names %s as the "
                "sample %s are judged on; a surface that names none cannot be "
                "cross-checked"
                % (claim["key"], sorted(news_stages) or "nothing",
                   sorted(help_stages) or "nothing", claim["what"]))
        elif news_stages != help_stages:
            problems.append(
                "%s: NEWS.md and pkg/csdid.sthlp disagree about the sample %s "
                "are judged on. NEWS.md only: %s. Help only: %s"
                % (claim["key"], claim["what"],
                   sorted(news_stages - help_stages) or "-",
                   sorted(help_stages - news_stages) or "-"))

    checked += check_bootstrap_default(problems)

    if not checked:
        problems.append("no claim was cross-checked -- this gate is checking "
                        "nothing")

    if problems:
        for p in problems:
            print("FAIL: %s" % p, file=sys.stderr)
        print("\nNEWS.md ships in the release payload and the help ships with "
              "net install.\nA user reads both; they must name the same sample "
              "for the same refusal.", file=sys.stderr)
        return 1

    print("NEWS/help agreement ok (%d claim%s cross-checked)"
          % (checked, "" if checked == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
