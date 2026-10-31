#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    'historical_website', root / 'tools/release/check-historical-website.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
checked = 0


def refused(call, label):
    global checked
    try:
        call()
    except ValueError:
        checked += 1
        return
    raise AssertionError('historical publication accepted: ' + label)


def put(base, relative, content):
    path = base / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path


tag = 'a1ef9ef20b2d2a29c6d097712a10165b0116a43b'
commit = 'f98bcea0691b1670c409bb7e3cc81d60705b4f84'
checker.check_reference_identity(tag, commit)
refused(lambda: checker.check_reference_identity('0' * 40, commit), 'wrong tag object')
refused(lambda: checker.check_reference_identity(tag, '0' * 40), 'wrong peeled commit')

with tempfile.TemporaryDirectory(prefix='csdid-historical-publication-') as temporary:
    work = Path(temporary)
    baseline, candidate = work / 'baseline', work / 'candidate'
    files = {
        'tools/bench/field/results/metadata.json': '{"candidate_version":"2.0.1"}\n',
        'tools/bench/field/results/runs.csv': 'trial,seconds\n1,0.5\n',
        'tools/bench/field/historical-results/old.csv': 'trial,seconds\n1,10\n',
        'tools/bench/protocol.py': '# measured recipe\n',
        'website/assets/img/field-speed.png': 'synthetic image bytes\n',
        'tools/release/check-website-speed-tables.py': '# table verifier\n',
        'tools/release/check-website-speed-prose.py': '# prose verifier\n',
        'tests/meta/test-website-speed-claims.sh': '# claim verifier\n',
        'tools/release/sync-code-appendix.py': '# appendix verifier\n',
    }
    for relative, content in files.items():
        put(baseline, relative, content)
        put(candidate, relative, content)
    checker.verify_evidence(candidate, baseline)
    for relative, content in files.items():
        path = candidate / relative
        path.write_text(content + 'changed evidence or verification\n')
        refused(lambda: checker.verify_evidence(candidate, baseline), relative)
        path.write_text(content)
    missing = candidate / 'tools/bench/protocol.py'
    missing.unlink()
    refused(lambda: checker.verify_evidence(candidate, baseline), 'missing measured recipe')
    missing.write_text(files['tools/bench/protocol.py'])
    for relative in ('tools/bench/field/results/unrecorded.csv',
                     'tools/bench/field/historical-results/unrecorded.csv',
                     'website/assets/img/unrecorded.png'):
        extra = put(candidate, relative, 'unrecorded evidence\n')
        refused(lambda: checker.verify_evidence(candidate, baseline), 'extra ' + relative)
        extra.unlink()
    checker.verify_evidence(candidate, baseline)

    disclosure = work / 'disclosure'
    pages = ('website/articles/csdid-against-the-field.md',
             'website/articles/speed-vs-182.md', 'website/code-appendix.md')
    # This fixture describes historical publication independently of the
    # current release's version or whether its benchmarks have been refreshed.
    current_version = '2.0.9'
    for relative in pages:
        put(disclosure, relative,
            '---\nbenchmark_version: 2.0.1\n---\n\n# Historical measurements\n')
    put(disclosure, 'website/_layouts/default.html',
        '{% if page.benchmark_version %}\n'
        '<div class="benchmark-scope"><p>'
        'Measured with {{ page.benchmark_version }}. '
        f'Version {current_version} has not been remeasured.'
        '</p></div>\n{% endif %}\n')
    put(disclosure, 'website/index.md',
        '# Synthetic release\n\n## Speed\n\n'
        f'Version 2.0.1 measurements; Version {current_version} has not been '
        'remeasured.\n\n## Other material\n')
    for relative in ('pkg/csdid.ado', 'src/ado/csdid.ado'):
        put(disclosure, relative, f'*! csdid {current_version} synthetic fixture\n')
    checker.validate_disclosure(disclosure)
    for relative in pages:
        path = disclosure / relative
        original = path.read_text()
        changed, count = re.subn(r'^benchmark_version:.*$', 'benchmark_version: 2.0.2',
                                original, count=1, flags=re.M)
        assert count == 1, relative
        path.write_text(changed)
        refused(lambda: checker.validate_disclosure(disclosure), 'retagged ' + relative)
        path.write_text(original)
    absent = disclosure / pages[0]
    original = absent.read_text()
    absent.unlink()
    refused(lambda: checker.validate_disclosure(disclosure), 'missing benchmark page')
    absent.write_text(original)
    layout = disclosure / 'website/_layouts/default.html'
    original = layout.read_text()
    for token in ('page.benchmark_version', 'benchmark-scope', 'has not been remeasured',
                  f'Version {current_version}'):
        assert token in original, token
        layout.write_text(original.replace(token, 'removed scope'))
        refused(lambda: checker.validate_disclosure(disclosure), 'missing layout ' + token)
    scope = re.search(r'<div[^>]*\bbenchmark-scope\b[^>]*>.*?</div>', original, re.S)
    assert scope, 'visible result-scope element is missing'
    for label, opening, closing in (('HTML', '<!--', '-->'),
                                    ('Liquid', '{% comment %}', '{% endcomment %}')):
        layout.write_text(original[:scope.start()] + opening + scope.group() + closing
                          + original[scope.end():])
        refused(lambda: checker.validate_disclosure(disclosure), label + '-commented result scope')
    layout.write_text(original)
    home = disclosure / 'website/index.md'
    original = home.read_text()
    changed, count = re.subn(r'(?ms)^## Speed\n.*?(?=^## )',
                            '## Speed\n\nUnattributed timing claims.\n\n', original, count=1)
    assert count == 1
    home.write_text(changed)
    refused(lambda: checker.validate_disclosure(disclosure), 'missing homepage timing scope')
    home.write_text(original)
    checker.validate_disclosure(disclosure)
    source = disclosure / 'src/ado/csdid.ado'
    package = disclosure / 'pkg/csdid.ado'
    source_text, package_text = source.read_text(), package.read_text()
    package.write_text('*! csdid 2.0.1 synthetic fixture\n')
    refused(lambda: checker.validate_disclosure(disclosure), 'different source/package versions')
    source.write_text('*! csdid 2.0.1 synthetic fixture\n')
    refused(lambda: checker.validate_disclosure(disclosure), 'current release is not newer')
    source.write_text(source_text)
    package.write_text(package_text)
    checker.validate_disclosure(disclosure)

    # A fake publisher tree stops at each speed gate in turn. No Jekyll build,
    # estimator, site mutation or network request can occur on these paths.
    publisher = work / 'publisher'
    script = publisher / 'tools/release/publish-website.sh'
    put(publisher, 'tools/release/publish-website.sh',
        (root / 'tools/release/publish-website.sh').read_text())
    put(publisher, 'website/index.md', '# Synthetic publication\n')
    subprocess.run(['git', 'init', '-q', str(publisher)], check=True)
    subprocess.run(['git', '-C', str(publisher), 'add', 'website'], check=True)
    subprocess.run(['git', '-C', str(publisher), '-c', 'user.name=Fixture',
                    '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Fixture'], check=True)
    fake_bin = work / 'bin'
    fake_bin.mkdir()
    jekyll = put(fake_bin, 'jekyll',
                 '#!/usr/bin/env bash\nprintf "jekyll\\n" >> "$JEKYLL_CALLS"\nexit 99\n')
    jekyll.chmod(0o755)
    site = work / 'site'
    (site / '.git').mkdir(parents=True)
    calls = work / 'calls.txt'
    jekyll_calls = work / 'jekyll-calls.txt'
    env = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ['PATH'],
               CSDID_SITE_ROOT=str(site), GATE_CALLS=str(calls),
               JEKYLL_CALLS=str(jekyll_calls))
    put(publisher, 'tools/release/lint-website.sh', '#!/usr/bin/env bash\nexit 0\n')
    for label in ('tables', 'prose'):
        put(publisher, f'tools/release/check-website-speed-{label}.py',
            "import os, pathlib, sys\n"
            f"label={label!r}\n"
            "with pathlib.Path(os.environ['GATE_CALLS']).open('a') as f: f.write(label+'\\n')\n"
            "sys.exit(61 if os.environ['FAIL_GATE']==label else 0)\n")
    put(publisher, 'tests/meta/test-website-speed-claims.sh',
        '#!/usr/bin/env bash\nprintf "claims\\n" >> "$GATE_CALLS"\n'
        'if [ "$FAIL_GATE" = claims ]; then exit 61; fi\n')
    put(publisher, 'tests/meta/test-reliability-tables.sh', '#!/usr/bin/env bash\nexit 97\n')
    for index, label in enumerate(('tables', 'prose', 'claims'), 1):
        calls.unlink(missing_ok=True)
        result = subprocess.run(['bash', str(script)], env=dict(env, FAIL_GATE=label),
                                capture_output=True, text=True)
        assert result.returncode == 61, (label, result.stdout, result.stderr)
        assert calls.read_text().splitlines() == ['tables', 'prose', 'claims'][:index]
        assert not jekyll_calls.exists(), 'default evidence failure reached Jekyll'
        checked += 1
    calls.unlink(missing_ok=True)
    result = subprocess.run(['bash', str(script), '--unsupported-publication-mode'],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 2, (result.returncode, result.stdout, result.stderr)
    assert '--unsupported-publication-mode' in result.stdout + result.stderr
    assert not calls.exists(), 'unknown argument reached evidence gates'
    assert not jekyll_calls.exists(), 'unknown argument reached Jekyll'
    checked += 1
    result = subprocess.run(['bash', str(script), '--historical-evidence'],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 2, (result.returncode, result.stdout, result.stderr)
    assert not calls.exists(), 'missing reference reached evidence gates'
    assert not jekyll_calls.exists(), 'missing reference reached Jekyll'
    checked += 1

print(f'Historical website publication: valid fixtures and {checked} refusal/default-gate cases pass.')
PY
