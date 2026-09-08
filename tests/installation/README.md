# Installation tests

A small, self-contained check that the package installs into a clean Stata
session and runs. It points `PLUS` and `PERSONAL` at temporary directories,
installs from the local package manifest, estimates on the bundled example
data, and confirms the expected results come back. In an extracted bundle it
also exercises `install.do`. The shell runner requires a fresh, completed
Stata batch log without an uncaught error before reporting success.

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

From a complete repository checkout, run:

```bash
bash tests/installation/run-install-smoke.sh
```
