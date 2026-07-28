# Installation tests

A small, self-contained check that the package installs into a clean Stata
session and runs. It points `PLUS` and `PERSONAL` at temporary directories,
installs from `install.do`, estimates on the bundled example data, and confirms
the expected results come back.

These are deliberately minimal: they verify that a distributed copy works, not
that it is numerically correct. The parity suite lives in `tests/stata/` and
`tests/fixtures/`.

They are copied into the release bundle as `validation-tests/`. Run from the
extracted bundle root:

```bash
bash validation-tests/run-install-smoke.sh
```

or from Stata:

```stata
do validation-tests/install-and-smoke.do
```
