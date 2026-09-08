#!/usr/bin/env bash
# Synthetic records qualify attribution checks; they are never release evidence.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
import csv
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path('tools/release/check-final-release-evidence.py').resolve()
with tempfile.TemporaryDirectory(prefix='csdid-evidence-check-') as temp:
    repo = Path(temp)
    checker = repo / 'tools/release/check-final-release-evidence.py'
    checker.parent.mkdir(parents=True)
    shutil.copy2(source, checker)
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    marker = repo / 'synthetic-candidate.txt'
    marker.write_text('Synthetic qualification only.\n')
    subprocess.run(['git', '-C', str(repo), 'add', marker.name], check=True)
    env = os.environ | {'GIT_AUTHOR_NAME': 'Qualification Fixture',
                       'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
                       'GIT_COMMITTER_NAME': 'Qualification Fixture',
                       'GIT_COMMITTER_EMAIL': 'fixture@example.invalid'}
    subprocess.run(['git', '-C', str(repo), '-c', 'commit.gpgsign=false',
                    'commit', '-qm', 'Synthetic candidate'], env=env, check=True)
    candidate = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    bundle = repo / 'synthetic-bundle.txt'
    bundle.write_bytes(b'Synthetic artifact for checker qualification; not a release.\n')
    digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
    evidence = repo / 'evidence'
    evidence.mkdir()
    header = ['date', 'stata_version', 'edition', 'os', 'machine_type', 'byteorder',
              'release_gates_status', 'repository_commit', 'production_digest']
    rows = {
        'macos-platform.csv': ['7 Sep 2026', '17', 'MP', 'Unix', 'Mac (Apple Silicon)', 'lohi', 'pass', candidate, '1' * 64],
        'windows-platform.csv': ['2026-09-07', '17', 'SE', 'Windows', 'PC (64-bit x86-64)', 'lohi', 'pass', candidate, '2' * 64],
        'linux-platform.csv': ['2026-09-07', '19.5', 'MP', 'Unix', 'PC (64-bit x86-64)', 'lohi', 'pass', candidate, '3' * 64],
    }
    signoffs = ['stata-mata-review-signoff.md', 'econometrics-review-signoff.md']
    owner = 'release-owner-decision.md'
    originals = {}
    for filename, row in rows.items():
        out = io.StringIO()
        csv.writer(out).writerows([header, row])
        originals[filename] = out.getvalue()
    for i, filename in enumerate(signoffs):
        originals[filename] = (f'Reviewer: Synthetic reviewer {i}\nDate: 2026-09-07\n'
            f'Repository commit: {candidate}\nStata version/edition: 17 MP\n'
            'Operating system: macOS\nR did source: Synthetic pinned source record\n'
            '| ID | Severity | Finding | Disposition |\n'
            'Final release approved: yes\nBlocking findings remaining: none\n')
    originals[owner] = (f'Release owner: Synthetic owner\nDate: 2026-09-07\n'
        f'Repository commit: {candidate}\nBundle SHA256: {digest}\n'
        'Final release approved: yes\nBlocking findings remaining: none\n')

    def reset():
        for name, value in originals.items():
            (evidence / name).write_text(value)

    def replace(name, old, new):
        path = evidence / name
        text = path.read_text()
        assert old in text, (name, old)
        path.write_text(text.replace(old, new, 1))

    def platform(name, **changes):
        row = dict(zip(header, rows[name])) | changes
        with (evidence / name).open('w', newline='') as fh:
            csv.writer(fh).writerows([header, [row[key] for key in header]])

    count = 0
    def run(label, ok=False, commit=None, artifact=None, marker=None):
        global count
        command = ['python3', str(checker), '--evidence-dir', str(evidence),
                   '--candidate-commit', candidate if commit is None else commit,
                   '--bundle', str(bundle if artifact is None else artifact)]
        p = subprocess.run(command, text=True, capture_output=True, timeout=20)
        output = p.stdout + p.stderr
        if (p.returncode == 0) != ok or 'Traceback' in output or (marker and marker not in output):
            raise AssertionError(f'{label}: exit {p.returncode}\n{output}')
        count += 1

    reset(); run('valid attributed inventory with distinct platform digests', True)
    platform('macos-platform.csv', stata_version='15', edition='IC')
    platform('linux-platform.csv', stata_version='17', edition='SE')
    run('documented platform floors and editions', True)
    reset()
    platform('macos-platform.csv', os='Darwin', machine_type='arm64')
    platform('linux-platform.csv', os='Linux', machine_type='x86_64')
    replace(signoffs[0], '17 MP', 'StataNow 19.5/MP')
    run('explicit OS labels and reviewer version notation', True)
    reset()
    with (evidence / 'linux-platform.csv').open('a', newline='') as fh:
        csv.writer(fh).writerow(rows['linux-platform.csv'])
    run('multiple valid platform rows', True)

    for field, value in [('os', 'Plan9'), ('os', 'banana'), ('machine_type', 'generic PC'),
                         ('machine_type', 'Oracle Solaris'), ('machine_type', 'Unlisted workstation'),
                         ('stata_version', 'TBD'), ('stata_version', 'NaN'), ('stata_version', '9' * 400), ('stata_version', '0'),
                         ('stata_version', '16'), ('edition', 'pending'), ('edition', 'IC'),
                         ('release_gates_status', 'failed'), ('repository_commit', 'deadbeef'),
                         ('repository_commit', 'f' * 40), ('production_digest', 'nonempty'),
                         ('production_digest', 'g' * 64), ('date', '2026-02-30'),
                         ('byteorder', 'unknown')]:
        reset(); platform('linux-platform.csv', **{field: value}); run('invalid Linux ' + field + '=' + value)
    for name, changes in [('windows-platform.csv', {'os': 'Darwin'}),
                          ('windows-platform.csv', {'machine_type': 'Mac (Intel)'}),
                          ('macos-platform.csv', {'stata_version': '14'}),
                          ('macos-platform.csv', {'machine_type': 'PC (Linux 64-bit)'})]:
        reset(); platform(name, **changes); run('platform mismatch ' + name)
    for field, value in [('release_gates_status', 'failed'), ('repository_commit', 'f' * 40),
                         ('stata_version', 'TBD'), ('os', 'Plan9')]:
        reset()
        bad = dict(zip(header, rows['linux-platform.csv'])) | {field: value}
        with (evidence / 'linux-platform.csv').open('a', newline='') as fh:
            csv.writer(fh).writerow([bad[key] for key in header])
        run('invalid second row ' + field, marker='row 3')
    for field in header:
        reset()
        selected = [key for key in header if key != field]
        with (evidence / 'linux-platform.csv').open('w', newline='') as fh:
            csv.writer(fh).writerows([selected, [dict(zip(header, rows['linux-platform.csv']))[key] for key in selected]])
        run('missing column ' + field)
    for label, content in [
        ('duplicate header', originals['linux-platform.csv'].replace('date,', 'date,date,', 1)),
        ('extra row field', originals['linux-platform.csv'].rstrip() + ',extra\n'),
        ('missing row field', originals['linux-platform.csv'].rsplit(',', 1)[0] + '\n'),
        ('no rows', ','.join(header) + '\n'), ('empty file', ''),
        ('invalid CSV quoting', ','.join(header) + '\n"unterminated')]:
        reset(); (evidence / 'linux-platform.csv').write_text(content); run(label)
    for filename in [*signoffs, owner]:
        for field, value in [('Repository commit', 'f' * 40), ('Date', 'TBD'),
                             ('Final release approved', 'no'), ('Blocking findings remaining', 'pending')]:
            reset()
            prior = {'Repository commit': candidate, 'Date': '2026-09-07',
                     'Final release approved': 'yes', 'Blocking findings remaining': 'none'}[field]
            replace(filename, field + ': ' + prior, field + ': ' + value)
            run(filename + ' invalid ' + field)
        reset(); (evidence / filename).write_text(originals[filename] + 'Final release approved: no\n')
        run(filename + ' duplicate approval')
    for field, value in [('Reviewer', '[pending]'), ('Stata version/edition', 'TBD'),
                         ('Stata version/edition', '17 imaginary'), ('Operating system', 'n/a')]:
        reset()
        prior = {'Reviewer': 'Synthetic reviewer 0', 'Stata version/edition': '17 MP', 'Operating system': 'macOS'}[field]
        replace(signoffs[0], field + ': ' + prior, field + ': ' + value)
        run('placeholder or invalid reviewer ' + field)
    reset(); replace(signoffs[1], 'Synthetic pinned source record', 'TBD'); run('missing oracle source')
    reset(); replace(signoffs[0], '| ID | Severity |', '| Finding |'); run('missing findings table')
    for value in ['nonempty', 'g' * 64, 'f' * 64]:
        reset(); replace(owner, digest, value); run('invalid or mismatched owner hash')
    for filename in originals:
        reset(); (evidence / filename).unlink(); run('missing ' + filename)
    reset(); (evidence / signoffs[0]).write_bytes(b'\xff'); run('unreadable evidence')
    reset()
    for value in ['HEAD', candidate[:8], 'g' * 40, 'f' * 40]:
        run('invalid explicit candidate ' + value, commit=value)
    for artifact in [repo / 'absent-bundle', repo]:
        run('invalid bundle path', artifact=artifact)
    empty = repo / 'empty'; empty.write_bytes(b'')
    run('empty bundle', artifact=empty)
    other = repo / 'other-bundle'; other.write_bytes(b'Different synthetic bytes.\n')
    run('changed actual bundle', artifact=other)
    print(f'Final release evidence: {count} synthetic qualification cases passed')
PY
