# Branches and releases

Two repositories, and it matters which is which.

| Repository | What it is | Trunk |
| --- | --- | --- |
| `pedrohcgs/csdid-stata` | The package users install. Public. | `main` |
| `pedrohcgs/csdid` | Development, with the full fixture and audit history. | `main` |

Work happens in the porting repository. Releases are cut from it into
`csdid-stata`, which is what `net install` reads.

## Branch names

`main` is the trunk in both. It was previously
`codex/csdid-goal-terminal-gates` in the porting repository — a name inherited
from the tool that created it, which meant every pull request defaulted to a
branch whose name told a reader nothing, and every fresh clone landed there.

Work branches take a prefix that says what the change is:

| Prefix | For | Example |
| --- | --- | --- |
| `feat/` | new user-visible capability | `feat/clustered-analytical-se` |
| `fix/` | a defect in shipped behaviour | `fix/matastrict-session-leak` |
| `perf/` | speed or memory, results bit-identical | `perf/rcs-setup-vectorisation` |
| `docs/` | documentation and the website | `docs/base-period-guide` |
| `test/` | tests, fixtures, oracles | `test/inherit-unbalanced-inference` |
| `chore/` | tooling, packaging, repository hygiene | `chore/track-untracked-gates` |
| `release/` | a release being prepared | `release/2.0.0` |

Lower case, hyphen separated, no personal or tool names. `pedrohcgs-patch-1`
and `codex/...` are what GitHub's web editor and agent tooling produce by
default; rename them before opening a pull request.

Keep the subject short enough to read in a branch list. The pull request
carries the explanation.

## Releases

A release is a `release/x.y.z` branch on `csdid-stata`, opened as a pull
request against `main` there, carrying:

- the installable package (`pkg/`, `csdid.pkg`, `stata.toc`)
- the source (`src/`), the suite (`tests/`), `examples/`, `tools/`
- `README.md`, `NEWS.md`, `LICENSE`, `docs/`, `website/`

`NEWS.md` leads with anything that can change a user's results.

The two repositories share no history, so a release is a fresh branch built on
`csdid-stata`'s `main` rather than a pull request across repositories — GitHub
cannot open one between unrelated histories.

## Before a pull request

`docs/merge-protocol.md` is the checklist. The short form: a fully green
`tools/release/preflight.sh` with no `BLOCKED` tier. There is no hosted CI —
Stata is licence-locked — so a pre-push hook checks a receipt that preflight
writes only on a complete, fully green run, pinned to a digest of the code it
exercised. Do not route around it.
