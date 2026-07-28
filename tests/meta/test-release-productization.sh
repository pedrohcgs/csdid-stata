#!/usr/bin/env bash
set -euo pipefail

for path in \
  docs/verification-criteria.md \
  docs/release-checklist.md \
  inst/spec/feature-matrix.csv \
  reports/implementation-status.md \
  reports/engineering-audit.md \
  reports/hardening-status.md; do
  grep -qE 'F051' "$path"
done
# NEWS.md deliberately carries no fixture IDs. It is the user-facing changelog
# for the upgrade from csdid 1.82, and F051 -- like every other fixture id --
# means nothing to a reader upgrading their do-files. The evidence requirement
# is unchanged: F051 is still asserted in the docs, reports and feature matrix
# above, which is where verification evidence belongs.
grep -qE 'csdid 2\.0\.0' NEWS.md

for path in \
  docs/versioning-and-release-policy.md \
  docs/stored-results-api.md \
  docs/bootstrap-scope.md \
  docs/platform-matrix.md \
  docs/independent-review-packet.md \
  docs/release-notes-v2.0.0-rc1.md \
  docs/final-release-certification.md \
  docs/public-api-freeze-v2.md \
  docs/parser-refactor-plan.md \
  docs/support-runbook.md \
  docs/adversarial-differential-testing.md \
  docs/release-engineering.md \
  docs/worldwide-release-governance.md \
  docs/handoff-release-candidate-readme.md; do
  test -s "$path"
done

# POLICY (2026-07-27): the manuals and help files present csdid as a
# stand-alone Stata implementation. This gate used to REQUIRE 'R {cmd:did}'
# and '2.5.1' in csdid.sthlp, and 'R-parity Stata implementation' in the
# package metadata that `net describe` shows. Those assertions enforced the
# opposite of the current policy and are replaced by the negative check
# below. Verification against R remains an engineering requirement and is
# documented in docs/ and NEWS.md, not in user-facing text.
if grep -rnE 'DRDID|R \{cmd:did\}|R did|R-parity|CRAN|ggdid|att_gt\(|aggte\(' src/help csdid.pkg stata.toc; then
  echo "user-facing help/package text must not present csdid as an R port" >&2
  exit 1
fi
grep -qE 'csdid_plot requires saving\(filename\)' src/ado/csdid_plot.ado
grep -qE 'supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance' src/ado/csdid_estat.ado
grep -qE 'estat[[:space:]]+attgt' src/help/csdid_postestimation.sthlp
grep -qE 'estat[[:space:]]+event' src/help/csdid_postestimation.sthlp
# The id() alias must stay documented. This used to be satisfied only by the
# R crosswalk table; assert against the options section, which is where the
# alias is actually described.
grep -qE 'id\(varname\)' src/help/csdid.sthlp
grep -qE 'vce\(cluster' src/help/csdid.sthlp
grep -qE 'wboot reps\(1000\) seed\(12345\)' src/help/csdid.sthlp
grep -qE 'csdid_stats' src/help/csdid_postestimation.sthlp
grep -qE 'event' src/help/csdid_postestimation.sthlp
grep -qE 'estat dynamic' src/help/csdid_postestimation.sthlp
grep -qE 'estat simple' src/help/csdid_postestimation.sthlp
grep -qE 'estat group' src/help/csdid_postestimation.sthlp
grep -qE 'estat calendar' src/help/csdid_postestimation.sthlp
grep -qE 'examples/' docs/release-checklist.md
grep -qE 'test-release-hardening.do' docs/release-checklist.md
grep -qE 'test-public-help-surface.sh' docs/release-checklist.md
grep -qE '2\.0\.0' docs/versioning-and-release-policy.md
grep -qE '2.0.0-rc1' docs/release-notes-v2.0.0-rc1.md
grep -qE 'e\(profile\).*diagnostic' docs/stored-results-api.md
grep -qE 'multiplier bootstrap' docs/bootstrap-scope.md
grep -qE 'platform matrix' docs/platform-matrix.md
grep -qE 'Independent Review Packet' docs/independent-review-packet.md
# User-facing text says nothing about R: csdid is presented as a stand-alone
# Stata implementation. This banner and the *! headers are the most visible text
# the package has -- `csdid version` and `which csdid` -- and both used to read
# "R-parity implementation".
grep -qE 'display as text "csdid version 2\.0\.0"' src/ado/csdid.ado
! grep -qE 'R-parity' <(grep '^\*!' src/ado/*.ado)
grep -qE 'test-release-failure-modes.do' docs/release-checklist.md
grep -qE 'run-adversarial-differential.py' docs/release-checklist.md
grep -qE 'check-final-release-evidence.py' docs/release-checklist.md
grep -qE 'Final Release Certification' docs/final-release-certification.md
grep -qE 'Public API Freeze' docs/public-api-freeze-v2.md
grep -qE 'Parser Refactor Plan' docs/parser-refactor-plan.md
grep -qE 'Support Runbook' docs/support-runbook.md
grep -qE 'Adversarial Differential Testing' docs/adversarial-differential-testing.md
grep -qE 'Release Engineering' docs/release-engineering.md
grep -qE 'Worldwide Release Governance' docs/worldwide-release-governance.md
grep -qE 'run-platform-release-row.sh' docs/platform-matrix.md
test -f tests/stata/test-release-failure-modes.do
test -f tools/release/run-adversarial-differential.py
test -f tools/release/check-final-release-evidence.py
test -f tools/release/run-platform-release-row.sh
test -f reports/templates/release-owner-decision.md
test -f reports/final-release/README.md
test -f .github/ISSUE_TEMPLATE/numerical-discrepancy.yml
test -f .github/ISSUE_TEMPLATE/bug-report.yml
test -f .github/ISSUE_TEMPLATE/performance-regression.yml
test -f .github/workflows/static-release-gates.yml
grep -qE 'Final release approved' reports/templates/stata-mata-review-signoff.md
grep -qE 'Blocking findings remaining' reports/templates/econometrics-review-signoff.md
grep -qE 'release_gates_status=pass' docs/final-release-certification.md

for cmd in csdid_estat csdid_stats csdid_plot; do
  test -f "src/help/${cmd}.sthlp"
  # Official Stata help files (and reghdfe) open with `{title:Title}` and a
  # {p2col} line naming the command; the older `{title:<cmd>}` form this gate
  # used to require is not the documented convention. Assert the standard shape,
  # and still require the file to identify its own command.
  grep -qE "\\{title:Title\\}" "src/help/${cmd}.sthlp"
  grep -qE "\\{p2col ?:.*${cmd}" "src/help/${cmd}.sthlp"
  grep -qE "\\{title:Syntax\\}" "src/help/${cmd}.sthlp"
  grep -qE "\\{title:Also see\\}" "src/help/${cmd}.sthlp"
  # The manifest must name the file in the TRACKED distribution directory.
  # It previously named build/, which .gitignore excludes, so every path the
  # manifest promised was untracked and a public `net install` fetched nothing.
  grep -qE "f pkg/${cmd}.sthlp" csdid.pkg
  test -f "pkg/${cmd}.sthlp"
  grep -qE "copy src/help/${cmd}.sthlp build/${cmd}.sthlp" src/build.do
done

if grep -rnE 'implementation scaffold|Postestimation scaffold|clean-room Stata port scaffold|not implemented in the scaffold|currently requires saving' \
  src/help csdid.pkg stata.toc src/ado/csdid_estat.ado src/ado/csdid_plot.ado; then
  echo "release-facing help/package/diagnostic text still exposes scaffold wording" >&2
  exit 1
fi
