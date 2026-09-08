#!/usr/bin/env bash
# Qualify release-compiler selection and fresh completion without launching Stata.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "${1:-$ROOT}" "${2:-}" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root=Path(sys.argv[1]).resolve()
only=sys.argv[2]
passed=[]
with tempfile.TemporaryDirectory(prefix='csdid-build-runtime-') as tmp:
    tmp=Path(tmp)
    def run(name, mode='good', expected=0, old_log=False, marker=True,
            selection='build', existing_marker=None, missing_checker=False,
            failed_archive=False, invalid_marker=False, extra_arg=False):
        if only and name != only:return
        tree=tmp/name
        release=tree/'tools/release';release.mkdir(parents=True)
        for file in ('build-package.sh','check-stata-log-tail.sh'):
            shutil.copy2(root/'tools/release'/file,release/file)
        if missing_checker:(release/'check-stata-log-tail.sh').unlink()
        bin_=tree/'bin';bin_.mkdir()
        fake=bin_/'builder with spaces'
        fake.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path('called.json').write_text(json.dumps([sys.argv[0],sys.argv[1:]]))
mode=os.environ['BUILD_CASE']
if mode=='silent':sys.exit(0)
text={'good':'build ran\\nend of do-file\\n.\\n',
      'nonzero':'end of do-file\\n','empty':'','truncated':'build began\\n',
      'error':'r(459);\\nend of do-file\\n',
      'unfinished':'end of do-file\\n. assert 1\\n'}[mode]
Path('build.log').write_text(text)
sys.exit(9 if mode=='nonzero' else 0)
''');fake.chmod(0o755)
        consumer=bin_/'consumer';shutil.copy2(fake,consumer)
        default=bin_/'stata-mp';shutil.copy2(fake,default)
        env=dict(os.environ,BUILD_CASE=mode,PATH=str(bin_)+os.pathsep+os.environ['PATH'])
        for key in ('CSDID_BUILD_STATA_CMD','STATA_CMD'):env.pop(key,None)
        chosen=default
        if selection=='build':
            env.update(CSDID_BUILD_STATA_CMD=str(fake),STATA_CMD=str(consumer));chosen=fake
        elif selection=='consumer':env['STATA_CMD']=str(consumer);chosen=consumer
        elif selection=='absent':env['CSDID_BUILD_STATA_CMD']=str(bin_/'absent')
        if old_log:(tree/'build.log').write_text('OLD BUILD\nend of do-file\n')
        if failed_archive:
            mv=bin_/'mv';mv.write_text('#!/bin/sh\nexit 7\n');mv.chmod(0o755)
        receipt=tree/('absent/receipt' if invalid_marker else 'fresh receipt')
        if existing_marker is not None:receipt.write_text(existing_marker)
        args=['bash',str(release/'build-package.sh')]
        if marker:args.append(str(receipt))
        if extra_arg:args.append('unexpected')
        result=subprocess.run(args,cwd=tmp,env=env,text=True,capture_output=True)
        assert (result.returncode==0)==(expected==0),(name,result.returncode,result.stdout,result.stderr)
        if expected==0:
            assert json.loads((tree/'called.json').read_text())==[str(chosen),['-b','do','src/build.do']],name
            if marker:assert receipt.read_text()=='CSDID-PACKAGE-BUILD-COMPLETE\n',name
        elif existing_marker is None:assert not receipt.exists(),name
        else:assert receipt.read_text()==existing_marker,name
        if old_log and not failed_archive:
            archives=list((tree/'build/build-logs').glob('build.*'))
            assert len(archives)==1 and archives[0].read_text()=='OLD BUILD\nend of do-file\n',name
        if failed_archive:
            assert (tree/'build.log').read_text()=='OLD BUILD\nend of do-file\n',name
            assert not (tree/'called.json').exists(),name
        passed.append(name)
    run('compiler-override')
    run('consumer-fallback',selection='consumer')
    run('default-fallback',selection='default')
    run('no-receipt-needed',marker=False)
    run('archive-prior-success',old_log=True)
    for mode in ('nonzero','silent','empty','truncated','error','unfinished'):
        run(mode,mode=mode,expected=1)
    run('stale-success-silent-builder',mode='silent',expected=1,old_log=True)
    run('missing-builder',selection='absent',expected=1)
    run('failed-archive',old_log=True,failed_archive=True,expected=1)
    run('missing-checker',missing_checker=True,expected=1)
    run('stale-receipt',existing_marker='CSDID-PACKAGE-BUILD-COMPLETE\n',expected=1)
    run('empty-receipt',existing_marker='',expected=1)
    run('failed-receipt-write',invalid_marker=True,expected=1)
    run('extra-argument',extra_arg=True,expected=1)
if not passed:raise AssertionError('no requested build case ran')
print(f'Build runtime: {len(passed)} qualification cases passed')
PY
