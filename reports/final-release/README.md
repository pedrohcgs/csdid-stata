# Final Release Evidence Directory

Populate this directory only when cutting final `v2.0.0`.

Current rc1 status, 2026-07-08: final evidence is intentionally incomplete.
The macOS row has `release_gates_status=pass` after the latest local gates and
full-JEL evidence refresh. The latest local full-JEL run passes against
regenerated R `did` 2.5.1; historical R artifact drift under the oracle repin
remains recorded separately for release-owner evidence disposition. Windows
and Linux platform rows, independent signoffs, and release-owner approval are
still required before final `v2.0.0`.

Required files:

- `stata-mata-review-signoff.md`
- `econometrics-review-signoff.md`
- `macos-platform.csv`
- `windows-platform.csv`
- `linux-platform.csv`
- `release-owner-decision.md`

Use the templates in `reports/templates/`. The final evidence checker rejects
empty templates, missing reviewer fields, missing platform gate status, and any
signoff that does not explicitly set:

```text
Final release approved: yes
Blocking findings remaining: none
```

Validate before tagging:

```bash
python3 tools/release/check-final-release-evidence.py --evidence-dir reports/final-release
```
