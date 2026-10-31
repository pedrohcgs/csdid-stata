#!/usr/bin/env bash
# Scratch input transport is checked without R or any numerical generator.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile

root = Path.cwd()
runner = Path(os.environ.get('CSDID_R_REGEN_RUNNER', root/'tools/release/regenerate-r-oracles.sh')).resolve()
checks = 0
with tempfile.TemporaryDirectory(prefix='csdid-oracle-input-') as temporary:
    work = Path(temporary)
    binary = work/'bin'
    binary.mkdir()
    fake_r = binary/'Rscript'
    fake_r.write_text(r'''#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re
import sys
root = Path.cwd()
with Path(os.environ['CSDID_TRANSPORT_CALLS']).open('a') as handle:
    handle.write(json.dumps({'argv':sys.argv[1:],'cwd':str(root)})+'\n')
assert sys.argv[1:] == ['tools/parity/generators/probe/generate.R']
profile = Path(os.environ['R_PROFILE_USER'])
assert profile.parent.resolve() == root.resolve() and 'CSDID_ATTEST_CALL' in profile.read_text()
manifest = root/'csdid.pkg'
if not manifest.is_file():
    raise SystemExit('transport probe cannot read scratch csdid.pkg')
source = Path(os.environ['CSDID_TRANSPORT_MANIFEST'])
if manifest.read_bytes() != source.read_bytes():
    raise SystemExit('transport probe scratch manifest bytes differ from source')
versions = re.findall(r'^d Version: (.*)$',manifest.read_text(),re.M)
if len(versions) != 1 or not versions[0].strip():
    raise SystemExit('transport probe requires one nonempty manifest version')
output = root/'tests/fixtures/parity/probe/expected/r/version.csv'
output.write_text('version\n'+versions[0].strip()+'\n')
if os.environ.get('CSDID_TRANSPORT_ATTEST') != 'no':
    print('CSDID_ATTEST_CALL',file=sys.stderr)
''')
    fake_r.chmod(0o755)
    fake_cp = binary/'cp'
    fake_cp.write_text(r'''#!/usr/bin/env python3
import os
import subprocess
import sys
if os.environ.get('CSDID_TRANSPORT_FAIL_COPY') == 'yes' and len(sys.argv)>2 and sys.argv[-2]=='csdid.pkg':
    raise SystemExit('transport probe manifest copy refused')
raise SystemExit(subprocess.call(['/bin/cp',*sys.argv[1:]]))
''')
    fake_cp.chmod(0o755)
    cases = ('future-version', 'later-version', 'missing-manifest', 'manifest-directory',
             'copy-failure', 'wrong-manifest-version', 'missing-attestation')
    for label in cases:
        project = work/label
        (project/'tools/release').mkdir(parents=True)
        shutil.copyfile(runner,project/'tools/release/regenerate-r-oracles.sh')
        generator = project/'tools/parity/generators/probe/generate.R'
        generator.parent.mkdir(parents=True)
        generator.write_text('# Modeled R manifest consumer; the stub tests transport, not estimator provenance.\n')
        expected = project/'tests/fixtures/parity/probe/expected/r/version.csv'
        expected.parent.mkdir(parents=True)
        version = '9.9.124' if label=='later-version' else '9.9.123'
        manifest = project/'csdid.pkg'
        manifest.write_text('v 3\nd Version: '+version+'\nd Transport sentinel: exact bytes\n')
        expected.write_text('version\n'+version+'\n')
        # A wrong-source mutant has a readable alternative to copy. Matching
        # version labels cannot conceal that its other bytes are different.
        (project/'inst').mkdir()
        (project/'inst/wrong.pkg').write_text('v 3\nd Version: '+version+'\nd Wrong source\n')
        if label=='missing-manifest':
            manifest.unlink()
        elif label=='manifest-directory':
            manifest.unlink()
            manifest.mkdir()
        elif label=='wrong-manifest-version':
            manifest.write_text(manifest.read_text().replace(version,'9.9.999'))
        calls = project/'R-calls.jsonl'
        env = dict(os.environ, PATH=str(binary)+os.pathsep+os.environ['PATH'],
                   CSDID_TRANSPORT_CALLS=str(calls), CSDID_TRANSPORT_MANIFEST=str(manifest),
                   CSDID_TRANSPORT_FAIL_COPY='yes' if label=='copy-failure' else 'no',
                   CSDID_TRANSPORT_ATTEST='no' if label=='missing-attestation' else 'yes')
        result = subprocess.run(['bash','tools/release/regenerate-r-oracles.sh'],cwd=project,
                                env=env,capture_output=True,text=True)
        body = result.stdout+result.stderr
        if label in ('future-version','later-version'):
            assert result.returncode==0, (label,body)
            assert 'R oracles regenerated and byte-identical: 1 generators, 1 files' in body
            assert len(calls.read_text().splitlines())==1
        else:
            assert result.returncode!=0, (label,'accepted invalid transport',body)
            if label in ('missing-manifest','manifest-directory'):
                assert 'requires root csdid.pkg' in body, (label,body)
                assert not calls.exists(), (label,'R launched before refusing required input')
            elif label=='copy-failure':
                assert 'could not copy root csdid.pkg' in body, body
                assert not calls.exists(), 'R launched after the required copy failed'
            elif label=='wrong-manifest-version':
                assert 'DIFFERS from what pinned R regenerates' in body, body
            else:
                assert 'without the reference estimator ever EXECUTING' in body, body
        checks += 1
print(f'Oracle scratch input transport: {checks} isolated stub cases pass; no R or Stata launched.')
PY
