#!/usr/bin/env python3
"""The shipped help files must read stand-alone, and every name in them must exist.

`tests/meta/test-public-help-surface.sh` greps fifteen lines of narrow patterns,
which between them guard six words. Text of each of the three kinds below
passes those greps unchanged:

  * a sentence naming another package  -- a forbidden reference on a public
    surface;
  * a dated note about what some run of the test suite turned up -- development
    history;
  * `counted before bal(full) does any dropping`  -- a factual claim inverted.

Only a literal fixture id such as `See fixture F049.` turns them red. This
checker is what guards the rest.

Three rules, in descending order of how much they can actually prove.

R1  R-PACKAGE REFERENCES.  Help files are self-contained.  The single
    approved exception is the Acknowledgments credit in csdid.sthlp,
    allowed here by its EXACT text: the paragraph is written out below and must
    appear byte-for-byte, exactly once, in that one file.  Editing it, moving
    it, or copying it into a second file is a failure, so the exception cannot
    stretch to cover a new reference.

R2  DEVELOPMENT HISTORY.  Session slugs, calendar dates, commit hashes, test
    identifiers, process vocabulary, and discovery narration.  This is a
    vocabulary rule: it catches the words internal process is written in, not
    the idea of internal process.

R3  FACTUAL CLAIMS.  Free prose cannot be checked mechanically and this does
    not pretend to.  What IS mechanical is every NAME and NUMBER the prose
    hangs on, and all four kinds are checked against the code:

      a. every option in an option table resolves in that command's ado --
         either declared in a `syntax' statement, at an abbreviation no shorter
         than the one the help promises, or matched literally in the
         catch-all alias block;
      b. every `e(name)' mentioned anywhere in the help is posted by some ado;
      c. every return code the help quotes is raised by the source;
      d. every matrix whose columns the help enumerates carries exactly those
         column names in `matrix colnames'.

    What remains unguarded is stated in the gate's own output, so a green run
    does not read as more than it is.

Exit 0 on success; print every violation with file and line, and exit 1
otherwise.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

PKG = os.path.join(ROOT, "csdid.pkg")
HELPDIR = os.path.join(ROOT, "src", "help")
ADODIR = os.path.join(ROOT, "src", "ado")
LEGACYDIR = os.path.join(ROOT, "src", "legacy")
MATADIR = os.path.join(ROOT, "src", "mata")

# Which ado owns which help file's options. Options are command-specific, so
# this mapping is what makes rule R3a strong: an option documented for csdid
# must be an option csdid.ado parses, not one some other command happens to
# have. estat delegates every aggregation to csdid_stats, so it reads both.
OPTION_OWNERS = {
    "csdid.sthlp": ["csdid.ado"],
    "csdid_stats.sthlp": ["csdid_stats.ado"],
    "csdid_estat.sthlp": ["csdid_estat.ado", "csdid_stats.ado"],
    "csdid_plot.sthlp": ["csdid_plot.ado"],
    "csdid_postestimation.sthlp": [],
    "csdid_legacy.sthlp": [],
}


# ---------------------------------------------------------------------------
# The one approved exception, written out in full.
#
# Anchoring on the exact text rather than on a pattern is deliberate. A pattern
# broad enough to permit this paragraph -- "allow R references in the
# Acknowledgments" -- would also permit the next one written there, and the
# whole value of the rule is that there is no next one.
# ---------------------------------------------------------------------------
APPROVED_R_CREDIT_FILE = "csdid.sthlp"
APPROVED_R_CREDIT = """{phang}
The R package {bf:did}, by Brantly Callaway and Pedro H. C. Sant'Anna, is the
reference implementation of these methods. {cmd:csdid} derives from it and was
constructed and benchmarked against {bf:did} version 2.5.1: the estimators and
the sample rules follow it, and the group-time effects,
their aggregations, and their standard errors are checked directly against it.
{p_end}"""


# ---------------------------------------------------------------------------
# R1 patterns.
#
# `bare-R' is the load-bearing one: a standalone capital R appears exactly once
# in all six shipped files, inside the approved credit. Stata's own Base
# Reference Manual citations are written `[R] command' in {vieweralsosee}
# lines, so that bracketed token is removed before the scan rather than
# pattern-matched around.
#
# The identifier list is curated, not generated. Generating it from the R
# sources would sweep in every name the two packages share by design --
# base_period, biters, cband, control_group, min_e, na.rm, nevertreated -- and
# those are csdid's own documented option and e() spellings. Only names that
# exist on the R side and nowhere in csdid's surface are listed.
# ---------------------------------------------------------------------------
R_IDENTIFIERS = [
    "att_gt", "aggte_obj", "mboot", "pre_process_did", "pre_process_did2",
    "compute[.]att_gt", "compute[.]att_gt2", "compute[.]aggte",
    "process_attgt", "DIDparams", "DIDparams2", "AGGTEobj", "MP[.]TEST",
    "conditional_did_pretest", "drdid_panel", "drdid_rc", "DRDID", "BMisc",
    "fastglm", "xformla", "tname", "gname", "idname", "weightsname",
    "allow_unbalanced_panel", "faster_mode", "print_details",
    "compute_inffunc", "trimmer", "getSE", "ggdid", "multiplier_bootstrap",
    "makeBalancedPanel", "wif",
]

R_RULES = [
    ("bare-R",
     r"(?<![A-Za-z0-9_.])R(?![A-Za-z0-9_])",
     "a standalone `R'"),
    ("r-identifier",
     r"\b(?:" + "|".join(R_IDENTIFIERS) + r")\b",
     "an identifier from the R implementation"),
    ("r-source-file",
     r"\b[A-Za-z_][A-Za-z0-9_.]*\.R\b",
     "an R source file name"),
    ("r-package-phrase",
     r"\bCRAN\b|\bRscript\b|\blibrary\(|\b(?:did|DRDID|BMisc)::"
     r"|\bdid package\b|\{bf:did\}|\breference implementation\b"
     r"|\bR[- ]parity\b",
     "a phrase naming the R package"),
    ("r-oracle-version",
     r"\b2\.5\.1\b",
     "the R package's version number"),
]

# `[R] command' -- Stata's Base Reference Manual, not the R language.
STATA_MANUAL_TOKEN = re.compile(r"\[R\]")


# ---------------------------------------------------------------------------
# R2 patterns.
#
# The version header every help file carries -- `{* *! version 2.0.0 30jul2026}'
# -- is the one place a date belongs, and it is already gated for staleness by
# the shell wrapper. It is matched exactly and skipped, so that the date rule
# below can be absolute everywhere else.
# ---------------------------------------------------------------------------
VERSION_HEADER = re.compile(r"^\{\*\s*\*!\s*version\s+[0-9][0-9.]*\s+"
                            r"\d{1,2}[a-z]{3}\d{4}\}")

# Journal names in the References section that contain a word the
# process-vocabulary rule would otherwise flag. Listed by exact title and
# removed from the line before the scan, so `Review of Economic Studies' passes
# and a bare "Review" anywhere else still fails. Each entry must actually be
# cited somewhere in the help -- a title that stops being cited stops being an
# exemption, and the gate says so.
JOURNAL_TITLES = [
    "Review of Economic Studies",
]

HISTORY_RULES = [
    ("session-slug",
     r"\bsession-\d",
     "a session slug"),
    ("calendar-date",
     r"\b(?:19|20)\d{2}-\d{2}-\d{2}\b"
     r"|\b\d{1,2}(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"
     r"(?:19|20)\d{2}\b",
     "a calendar date"),
    ("commit-hash",
     r"\b(?=[0-9a-f]{7,40}\b)(?=[0-9a-f]*[a-f])(?=[0-9a-f]*[0-9])"
     r"[0-9a-f]{7,40}\b",
     "something shaped like a commit hash"),
    ("test-identifier",
     r"\bF-?\d{3}\b|\bf\d{3}\b|\brt\d{3}\b|\bfixtures?\b",
     "a test or fixture identifier"),
    ("process-vocabulary",
     r"(?i)\baudit\w*\b|\breview\w*\b|\bcollaborator\w*\b|\bblocker\w*\b"
     r"|\brefactor\w*\b|\bworktree\b|\bupstream\b|\boracle\b|\bpreflight\b"
     r"|\bgates?\b|\bhandoff\b|\bpull request\b|\bcommits?\b|\bbranch\w*\b"
     r"|\bmilestone\w*\b|\brelease candidate\b|\brc\d\b"
     r"|\bregression tests?\b|\bsmoke tests?\b",
     "development-process vocabulary"),
    ("discovery-narration",
     r"(?i)\bwe (?:found|discovered|noticed|fixed|repaired|reverted|decided|"
     r"realis\w+|realiz\w+)\b|\bwas found\b|\bwere found\b"
     r"|\bhas (?:since )?been (?:fixed|repaired|corrected)\b",
     "narration of how the package was developed"),
    ("work-marker",
     r"\bTODO\b|\bFIXME\b|\bXXX\b|\bWIP\b",
     "a work-in-progress marker"),
]


# ---------------------------------------------------------------------------
# R3: the grounded exemptions.
#
# Each list below is checked against the source in the direction that keeps it
# honest: an entry that stops being true stops being an exemption and turns the
# gate red, rather than quietly widening it.
# ---------------------------------------------------------------------------

# Posted by `ereturn post b V, esample()' rather than by name.
EPOST_RESULTS = ["b", "V", "sample"]

# Named in the help precisely to say the package does NOT store them. The
# checker asserts that no ado posts them; the day one does, this entry is wrong
# and the gate says so.
ABSENT_BY_DESIGN = ["ll"]

# Return codes Stata itself raises: 111 (a name Stata cannot resolve, quoted in
# the note about what a bare _b[] used to produce) and 322 (margins refusing on
# e(marginsnotok)). The checker asserts the source raises neither, so if csdid
# ever starts raising one, this entry has to be revisited.
STATA_OWN_RETURN_CODES = ["111", "322"]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def shipped_help_files():
    """The .sthlp files the install payload carries, resolved to their source."""
    names = re.findall(r"^f pkg/([A-Za-z0-9_]+\.sthlp)\s*$", read(PKG), re.M)
    if not names:
        return [], ["csdid.pkg lists no .sthlp files -- this gate would check "
                    "nothing"]
    problems = []
    paths = []
    for name in sorted(set(names)):
        src = os.path.join(HELPDIR, name)
        if not os.path.isfile(src):
            problems.append("csdid.pkg ships %s but src/help/%s does not exist"
                            % (name, name))
            continue
        paths.append(src)
        # The payload copy is what a user installs, and nothing else compares
        # the two. Everything below reads src/help; if pkg/ has drifted, the
        # file this checker cleared is not the file that ships.
        shipped = os.path.join(ROOT, "pkg", name)
        if not os.path.isfile(shipped):
            problems.append("csdid.pkg ships pkg/%s, which does not exist "
                            "(run: stata -b do src/build.do)" % name)
        elif read(shipped) != read(src):
            problems.append(
                "pkg/%s differs from src/help/%s -- the installed help is not "
                "the help this gate reads (run: stata -b do src/build.do)"
                % (name, name))
    for extra in sorted(os.listdir(HELPDIR)):
        src = os.path.join(HELPDIR, extra)
        if extra.endswith(".sthlp") and src not in paths:
            problems.append("src/help/%s is a help file csdid.pkg does not "
                            "ship -- add it to the payload or remove it"
                            % extra)
    return paths, problems


def ado_sources():
    out = []
    for d in (ADODIR, LEGACYDIR):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith(".ado"):
                out.append(os.path.join(d, name))
    return out


def approved_credit_lines(path, text):
    """Line numbers occupied by the approved Acknowledgments credit.

    Returns (set_of_line_numbers, problems).
    """
    problems = []
    count = text.count(APPROVED_R_CREDIT)
    base = os.path.basename(path)
    if base != APPROVED_R_CREDIT_FILE:
        if count:
            problems.append("%s: carries the approved Acknowledgments credit, "
                            "which belongs only in %s"
                            % (base, APPROVED_R_CREDIT_FILE))
        return set(), problems
    if count == 0:
        problems.append(
            "%s: the approved Acknowledgments credit is not present in its "
            "exact approved wording. It is the one place a help file may name "
            "the R package, and it is allowed by exact text, so any edit to it "
            "has to be re-approved and copied into "
            "tools/release/check-help-surface.py." % base)
        return set(), problems
    if count > 1:
        problems.append("%s: the approved Acknowledgments credit appears %d "
                        "times; it is allowed once" % (base, count))
    start = text.index(APPROVED_R_CREDIT)
    first = text.count("\n", 0, start) + 1
    span = APPROVED_R_CREDIT.count("\n") + 1
    return set(range(first, first + span)), problems


def strip_journal_titles(line):
    for title in JOURNAL_TITLES:
        line = line.replace(title, "")
    return line


def scan_patterns(path, text, rules, exempt_lines, prescrub=None):
    problems = []
    base = os.path.basename(path)
    for lineno, line in enumerate(text.split("\n"), 1):
        if lineno in exempt_lines:
            continue
        if VERSION_HEADER.match(line):
            continue
        scanned = prescrub(line) if prescrub else line
        for name, pattern, what in rules:
            hit = re.search(pattern, scanned)
            if hit:
                problems.append("%s:%d: %s -- %s (%s)"
                                % (base, lineno, what, hit.group(0).strip(),
                                   name))
    return problems


# ---------------------------------------------------------------------------
# R3a: options
# ---------------------------------------------------------------------------
PROGRAM = re.compile(r"^program\s+(?:define\s+)?([A-Za-z_][A-Za-z0-9_]*)",
                     re.M)
SYNTAX_BLOCK = re.compile(r"^\s*syntax\b(.*?)(?=\n\s*(?:[a-z_]+\s|\*|\}|$))",
                          re.M | re.S)
ARGUMENT_SPEC = re.compile(r"\((?:[^()]|\([^()]*\))*\)")
DECLARED = re.compile(r"(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9_]*)")
NOT_AN_OPTION = frozenset((
    "if", "in", "iw", "aw", "fw", "pw", "using", "anything", "varlist",
    "varname", "namelist", "newvarlist", "exp", "weight",
))


def main_program(ado_path, ado_text):
    """The body of the program whose name is the ado's own.

    Options are read from that program alone. Reading every `syntax' in the
    file would accept anything an internal helper parses -- `usecache()',
    `narm()', `bale()', `wbtype()' -- as though it were a user-facing option,
    which is exactly the kind of thing the help must not be allowed to promise.
    """
    want = os.path.basename(ado_path)[:-len(".ado")]
    starts = [(m.start(), m.group(1)) for m in PROGRAM.finditer(ado_text)]
    for i, (pos, name) in enumerate(starts):
        if name != want:
            continue
        end = starts[i + 1][0] if i + 1 < len(starts) else len(ado_text)
        return ado_text[pos:end]
    return None


def declared_options(program_text):
    """{full spelling: minimum abbreviation length} from the `syntax' lines."""
    out = {}
    for block in SYNTAX_BLOCK.findall(program_text):
        block = ARGUMENT_SPEC.sub(" ", block.replace("///", " "))
        for token in DECLARED.findall(block):
            if token.lower() in NOT_AN_OPTION:
                continue
            lead = re.match(r"[A-Z0-9_]*", token).group(0)
            minlen = len(lead) if lead else len(token)
            full = token.lower()
            out[full] = min(out.get(full, minlen), minlen)
    return out


def alias_literals(ado_text):
    """Option spellings matched literally in a catch-all block.

    Two shapes, and only two: a quoted string that is nothing but the option
    name (`inlist(`opt', "storeall", ...)'), and a quoted anchored regular
    expression (`regexm(`opt', "^(cluster|clustervars)\\((.*)\\)$")'). Anything
    else -- a name that merely occurs inside an error message, say -- does not
    count, so the exemption stays as narrow as the parsing it stands for.
    """
    out = set()
    for lit in re.findall(r'"([^"]*)"', ado_text):
        if re.fullmatch(r"[a-z_][a-z0-9_.]*", lit):
            out.add(lit)
        elif lit.startswith("^"):
            out.update(re.findall(r"[a-z_][a-z0-9_.]*", lit))
    return out


OPTION_TABLE = re.compile(r"\{synopthdr\}(.*?)\{synoptline\}\s*\{p2colreset\}",
                          re.S)
DOC_OPT = re.compile(r"\{opth?[: ]([A-Za-z_][A-Za-z0-9_]*)"
                     r"(?::([A-Za-z_][A-Za-z0-9_]*))?")
DOC_CMD_OPT = re.compile(r"\{synopt:\{cmd:([a-z_][a-z0-9_]*)\(")


def documented_options(help_text):
    """(full spelling, promised minimum abbreviation or None) per table entry."""
    out = {}
    for table in OPTION_TABLE.findall(help_text):
        for head, tail in DOC_OPT.findall(table):
            full = (head + (tail or "")).lower()
            out.setdefault(full, head.lower() if tail else None)
        for name in DOC_CMD_OPT.findall(table):
            out.setdefault(name.lower(), None)
    return out


def check_options(help_path, help_text, problems):
    base = os.path.basename(help_path)
    owners = OPTION_OWNERS.get(base)
    documented = documented_options(help_text)
    if owners is None:
        problems.append("%s: no ado is mapped to this help file, so its "
                        "options are unchecked -- add it to OPTION_OWNERS"
                        % base)
        return 0
    if not owners:
        return 0
    declared = {}
    literals = set()
    for ado in owners:
        path = os.path.join(ADODIR, ado)
        if not os.path.isfile(path):
            problems.append("%s: maps to %s, which does not exist" % (base, ado))
            continue
        text = read(path)
        body = main_program(path, text)
        if body is None:
            problems.append("%s: %s defines no program named %s, so its "
                            "options cannot be read" % (base, ado, ado[:-4]))
            continue
        for full, minlen in declared_options(body).items():
            declared[full] = min(declared.get(full, minlen), minlen)
        literals |= alias_literals(body)
    if not declared:
        problems.append("%s: read no options out of %s -- this check is "
                        "checking nothing" % (base, ", ".join(owners)))
        return 0
    for full, promised_min in sorted(documented.items()):
        target = None
        for cand, minlen in declared.items():
            if cand.startswith(full) and len(full) >= minlen:
                target = (cand, minlen)
                break
        if target is None:
            if full in literals:
                continue
            problems.append(
                "%s: documents option %s(), which %s neither declares in a "
                "syntax statement nor matches as a literal alias"
                % (base, full, " or ".join(owners)))
            continue
        cand, minlen = target
        if promised_min is not None and len(promised_min) < minlen:
            problems.append(
                "%s: documents %s as abbreviable to %s, but %s declares it as "
                "%s, whose shortest accepted form is %d characters"
                % (base, full, promised_min, " or ".join(owners), cand, minlen))
    return len(documented)


# ---------------------------------------------------------------------------
# R3b: stored results
# ---------------------------------------------------------------------------
EPOSTED = re.compile(r"ereturn\s+(?:hidden\s+)?(?:scalar|local|matrix)\s+"
                     r"([A-Za-z_][A-Za-z0-9_]*)")
EREF = re.compile(r"\be\(([A-Za-z_][A-Za-z0-9_]*)\)")


def check_stored_results(help_files, problems):
    posted = set()
    ados = ado_sources()
    joined = ""
    for path in ados:
        text = read(path)
        joined += text
        posted |= set(EPOSTED.findall(text))
    if not posted:
        problems.append("found no `ereturn scalar/local/matrix' names in "
                        "src/ado -- this check is checking nothing")
        return 0
    if "ereturn post" not in joined:
        problems.append("no ado calls `ereturn post', so e(b), e(V) and "
                        "e(sample) are not posted the way EPOST_RESULTS says "
                        "they are")
    for name in ABSENT_BY_DESIGN:
        if name in posted:
            problems.append(
                "e(%s) is listed as absent by design, but an ado now posts it "
                "-- the help says the package stores no e(%s); fix one of them "
                "and drop the entry from ABSENT_BY_DESIGN" % (name, name))
    allowed = posted | set(EPOST_RESULTS) | set(ABSENT_BY_DESIGN)
    checked = 0
    for path in help_files:
        base = os.path.basename(path)
        text = read(path)
        for lineno, line in enumerate(text.split("\n"), 1):
            for name in EREF.findall(line):
                checked += 1
                if name not in allowed:
                    problems.append(
                        "%s:%d: names e(%s), which no ado posts"
                        % (base, lineno, name))
    return checked


# ---------------------------------------------------------------------------
# R3c: return codes
# ---------------------------------------------------------------------------
DOC_RC = re.compile(r"(?:return code|rc|error)\s+(\d{3})\b|\br\((\d{3})\)")
RAISED_RC = re.compile(r"\b(?:exit|error|_error\()\s*\(?\s*(\d{3})\b")


def check_return_codes(help_files, problems):
    raised = set()
    sources = ado_sources()
    for d in (MATADIR,):
        if os.path.isdir(d):
            sources += [os.path.join(d, n) for n in sorted(os.listdir(d))
                        if n.endswith(".mata")]
    for path in sources:
        raised |= set(RAISED_RC.findall(read(path)))
    if not raised:
        problems.append("found no `exit NNN' / `error NNN' in the source -- "
                        "this check is checking nothing")
        return 0
    for code in STATA_OWN_RETURN_CODES:
        if code in raised:
            problems.append(
                "return code %s is listed as one Stata raises, not csdid, but "
                "the source now raises it -- drop it from "
                "STATA_OWN_RETURN_CODES" % code)
    allowed = raised | set(STATA_OWN_RETURN_CODES)
    checked = 0
    for path in help_files:
        base = os.path.basename(path)
        for lineno, line in enumerate(read(path).split("\n"), 1):
            for a, b in DOC_RC.findall(line):
                code = a or b
                checked += 1
                if code not in allowed:
                    problems.append(
                        "%s:%d: quotes return code %s, which the source never "
                        "raises" % (base, lineno, code))
    return checked


# ---------------------------------------------------------------------------
# R3d: matrix columns
# ---------------------------------------------------------------------------
COLNAMES = re.compile(r"matrix\s+colnames\s+`?([A-Za-z_][A-Za-z0-9_]*)'?\s*=\s*"
                      r"([A-Za-z_][A-Za-z0-9_ ]*)$", re.M)
SYNOPT_RESULT = re.compile(r"\{synopt:\{cmd:e\(([A-Za-z_][A-Za-z0-9_]*)\)\}\}"
                           r"(.*?)\{p_end\}", re.S)
CMD_TOKEN = re.compile(r"\{cmd:([a-z_][a-z0-9_]*)\}")


def matrix_columns():
    """{matrix name: set of column names} from `matrix colnames' in the ados."""
    out = {}
    for path in ado_sources():
        for name, cols in COLNAMES.findall(read(path)):
            names = cols.split()
            if len(names) < 2:
                continue
            out.setdefault(name, set()).update(names)
    return out


def check_matrix_columns(help_files, problems):
    columns = matrix_columns()
    if not columns:
        problems.append("found no `matrix colnames' in src/ado -- this check "
                        "is checking nothing")
        return 0
    checked = 0
    for path in help_files:
        base = os.path.basename(path)
        text = read(path)
        for name, body in SYNOPT_RESULT.findall(text):
            if name not in columns or "column" not in body:
                continue
            documented = set(CMD_TOKEN.findall(body))
            checked += 1
            missing = sorted(columns[name] - documented)
            invented = sorted(documented - columns[name])
            if missing:
                problems.append(
                    "%s: e(%s) carries column(s) %s, which its help entry does "
                    "not list" % (base, name, ", ".join(missing)))
            if invented:
                problems.append(
                    "%s: e(%s) is documented with column(s) %s, which "
                    "`matrix colnames' does not set"
                    % (base, name, ", ".join(invented)))
    return checked


def main():
    problems = []
    help_files, listing_problems = shipped_help_files()
    problems += listing_problems
    if not help_files:
        for p in problems:
            print(p, file=sys.stderr)
        return 1

    for path in help_files:
        text = read(path)
        exempt, exempt_problems = approved_credit_lines(path, text)
        problems += exempt_problems
        problems += scan_patterns(
            path, text, R_RULES, exempt,
            prescrub=lambda line: STATA_MANUAL_TOKEN.sub("", line))
        problems += scan_patterns(path, text, HISTORY_RULES, set(),
                                  prescrub=strip_journal_titles)

    corpus = "".join(read(p) for p in help_files)
    for title in JOURNAL_TITLES:
        if title not in corpus:
            problems.append(
                "%r is exempted from the process-vocabulary rule as a journal "
                "title, but no help file cites it -- drop it from "
                "JOURNAL_TITLES" % title)

    n_options = 0
    for path in help_files:
        n_options += check_options(path, read(path), problems)
    n_results = check_stored_results(help_files, problems)
    n_codes = check_return_codes(help_files, problems)
    n_matrices = check_matrix_columns(help_files, problems)

    if problems:
        print("public help surface: %d problem(s)" % len(problems),
              file=sys.stderr)
        for p in problems:
            print("   " + p, file=sys.stderr)
        print("", file=sys.stderr)
        print("Help files are self-contained: no R reference outside the one "
              "approved Acknowledgments credit, no development history, and "
              "every name checkable against the code.", file=sys.stderr)
        return 1

    print("public help surface OK across %d shipped help file(s):"
          % len(help_files))
    print("   payload: every pkg/ copy is byte-identical to its src/help "
          "source, so this is the help that installs")
    print("   R references: only the approved Acknowledgments credit, matched "
          "on its exact text")
    print("   development history: none of the %d vocabulary and shape rules "
          "fired" % len(HISTORY_RULES))
    print("   claims checked mechanically: %d documented options resolve in "
          "their ado, %d e() references are posted, %d return codes are "
          "raised, %d documented matrix column lists match `matrix colnames'"
          % (n_options, n_results, n_codes, n_matrices))
    print("   NOT checked: free prose. Whether a sentence describes what the "
          "code does -- what bal(full) drops and in which order, what e(N) "
          "counts, which estimator is the default, what a warning means -- is "
          "unverified here and needs a human reading the help against the ado "
          "and the Mata engine.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
