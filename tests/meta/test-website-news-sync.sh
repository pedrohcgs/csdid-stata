#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# One release narrative serves the package and the website. The site copy once
# retained old inference and performance claims after NEWS had been corrected.
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
news = root / "NEWS.md"
website = root / "website/news.md"
for path in (news, website):
    if not path.is_file():
        sys.exit(f"FAIL: missing release-news surface: {path.relative_to(root)}")
expected = b"---\ntitle: News\n---\n\n" + news.read_bytes()
if website.read_bytes() != expected:
    sys.exit("FAIL: website/news.md must equal NEWS.md with its News frontmatter; "
             "synchronize the release notes before publishing")
print("website release news matches NEWS.md")
PY
