#!/usr/bin/env bash
set -euo pipefail

doc="docs/legacy-migration-guide.md"
test -f "$doc"

grep -qF 'R `did` 2.5.1' "$doc"
grep -qF 'the default `bal(full)` drops the units not observed in every' "$doc"
grep -qF 'available only on request as `bal(pair)`' "$doc"
grep -qF '`method(dripw)`' "$doc"
grep -qF '`method(stdipw)`' "$doc"
grep -qF '`asinr`' "$doc"
grep -qF '`wboot(wtype(rademacher))`' "$doc"
grep -qF '`wboot(wtype(mammen))`' "$doc"
# wtype() and wbtype() are both accepted sub-option spellings, so an unsupported
# multiplier must be documented as failing under either. Pinning only one
# spelling let the guide imply the other was a way in.
grep -qF '`wtype()` and `wbtype()` are both accepted spellings of the sub-option' "$doc"
grep -qF '`wboot reps(#) seed(#)`, `wboot reps(#) rseed(#)`' "$doc"
grep -qF '`id(idvar)`' "$doc"
grep -qF '`notyettreated`, `nevertreated`' "$doc"
grep -qF '`vce(cluster clustvar)`' "$doc"
grep -qF '`csdid_stats event`, `csdid_stats, type(event)`' "$doc"
grep -qF '`estat dynamic`, `estat simple`, `estat group`, `estat calendar`' "$doc"
grep -qF '`bal(full)`, `balance(full)`, `bal(unbal)`' "$doc"
# Spellings that never shipped are stated as refusals, not as accepted aliases.
# A guide that still calls them deprecated spellings sends users to type
# something that exits 198.
grep -qF 'the vocabulary is `full`, `pair`, `none`, and anything else is refused with return code 198' "$doc"
grep -qF '`balance()` is the same option written out in full, not a second option' "$doc"
grep -qF 'Not options, and never were' "$doc"
# unbalanced is the documented spelling of the bal(none) synonym and
# allowunbalanced its longhand; neither is a casualty of the spellings above. A
# guide that lists them as refused sends users to rewrite working do-files.
grep -qF '`unbalanced`, `allowunbalanced`, `allow_unbalanced` | Supported, silent, and not deprecated' "$doc"
grep -qF '`unbalanced` is the documented spelling of the `bal(none)` synonym, typed in full' "$doc"
# The synonyms take no abbreviation. A guide that offers `unbal` sends users to
# type something that exits 198 and reads like the refused bal(unbal).
grep -qF 'No abbreviation of any of them is an option' "$doc"
# `! cmd` is exempt from set -e, so a bare negated grep here would never fail
# the gate no matter what the document said. Check it explicitly.
if grep -qF 'deprecated spelling of `bal(none)`' "$doc"; then
    echo "$doc still calls a never-shipped spelling a deprecated one" >&2
    exit 1
fi
grep -qF '`long`, `long2`' "$doc"
grep -qF 'Use the test suite under `tests/` as the migration map' "$doc"
grep -qF 'documented divergences' "$doc"
grep -qF 'None of them restores legacy per-comparison unit dropping' "$doc"
