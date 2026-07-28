#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATA_CMD="${STATA_CMD:-stata-mp}"
# Derived from the package version, never hardcoded: the default used to be
# csdid-stata-2.0.0-rc1-collaborator-2026-07-09, so running this today produced
# a bundle stamped with a stale date and an rc label that no longer applied.
VERSION="$(sed -n 's/^\*! csdid \([0-9][0-9.]*\).*/\1/p' src/ado/csdid.ado | head -1)"
if [ -z "$VERSION" ]; then
  echo "could not read the version from src/ado/csdid.ado" >&2
  exit 1
fi
BUNDLE_NAME="${1:-csdid-stata-${VERSION}}"
BUNDLE_DIR="dist/${BUNDLE_NAME}"
ZIP_PATH="dist/${BUNDLE_NAME}.zip"

copy_file() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

bash tools/plugin/build-bootstrap-plugin.sh auto
"$STATA_CMD" -b do src/build.do
bash tools/release/check-stata-log-tail.sh build.log

rm -rf "$BUNDLE_DIR" "$ZIP_PATH"
mkdir -p "$BUNDLE_DIR/build" "$BUNDLE_DIR/docs" "$BUNDLE_DIR/reports" \
  "$BUNDLE_DIR/validation" "$BUNDLE_DIR/validation-tests"

copy_file packaging/README.md "$BUNDLE_DIR/README.md"
copy_file NEWS.md "$BUNDLE_DIR/NEWS.md"
copy_file csdid.pkg "$BUNDLE_DIR/csdid.pkg"
copy_file stata.toc "$BUNDLE_DIR/stata.toc"
copy_file tools/release/handoff-install.do "$BUNDLE_DIR/install.do"

for f in \
  _csdid_post.ado \
  csdid.ado \
  csdid.mata \
  csdid.sthlp \
  csdid_estat.ado \
  csdid_estat.sthlp \
  csdid_plot.ado \
  csdid_plot.sthlp \
  csdid_postestimation.sthlp \
  csdid_stats.ado \
  csdid_stats.sthlp; do
  copy_file "build/$f" "$BUNDLE_DIR/build/$f"
done

plugin_count=0
for plugin in \
  csdid_bootstrap_macosx.plugin \
  csdid_bootstrap_unix.plugin \
  csdid_bootstrap_windows.plugin; do
  if [[ -f "build/$plugin" ]]; then
    copy_file "build/$plugin" "$BUNDLE_DIR/build/$plugin"
    printf 'f build/%s\n' "$plugin" >> "$BUNDLE_DIR/csdid.pkg"
    (
      cd "$BUNDLE_DIR"
      shasum -a 256 "build/$plugin"
    ) >> "$BUNDLE_DIR/validation/bootstrap-plugin-sha256.txt"
    plugin_count=$((plugin_count + 1))
  fi
done
if [[ "$plugin_count" -eq 0 ]]; then
  echo "no platform bootstrap plugin was built" >&2
  exit 1
fi

for f in \
  adversarial-differential-testing.md \
  bootstrap-scope.md \
  testing-protocol.md \
  validation-guide.md \
  final-release-certification.md \
  handoff-release-candidate-readme.md \
  independent-review-packet.md \
  legacy-migration-guide.md \
  legacy-stata-compatibility.md \
  model-improvement-required-tests.md \
  platform-matrix.md \
  public-v2.0.0-blockers.md \
  public-api-freeze-v2.md \
  release-checklist.md \
  release-engineering.md \
  release-notes-v2.0.0-rc1.md \
  stored-results-api.md \
  support-runbook.md \
  tolerance-registry-v1.md \
  verification-criteria.md \
  versioning-and-release-policy.md \
  worldwide-release-governance.md; do
  copy_file "docs/$f" "$BUNDLE_DIR/docs/$f"
done

for f in \
  engineering-audit.md \
  final-release-certification-status.md \
  hardening-status.md \
  legacy-candidate-performance-certification.md \
  jel-full-reproduction-result.md \
  jel-replication-summary.md \
  platform-matrix-local.csv \
  pre-signoff-econometrics-review.md \
  pre-signoff-stata-mata-review.md \
  release-next-steps-2026-07-09.md \
  release-candidate-readiness.md; do
  copy_file "reports/$f" "$BUNDLE_DIR/reports/$f"
done

cp -R reports/templates "$BUNDLE_DIR/reports/templates"
if [[ -d reports/final-release ]]; then
  cp -R reports/final-release "$BUNDLE_DIR/reports/final-release"
fi
cp -R examples "$BUNDLE_DIR/examples"
cp -R tests/installation/. "$BUNDLE_DIR/validation-tests"

copy_file build/f049/results.csv "$BUNDLE_DIR/validation/f049-stata-results.csv"
copy_file build/f049/r-results.csv "$BUNDLE_DIR/validation/f049-r-results.csv"
copy_file build/f049/r-stata-ratio.csv "$BUNDLE_DIR/validation/f049-r-stata-ratio.csv"
copy_file build/optin-performance/results.csv "$BUNDLE_DIR/validation/optin-performance-results.csv"
copy_file build/memory-gate/results.csv "$BUNDLE_DIR/validation/memory-gate-results.csv"
copy_file build/legacy-candidate-ab/runs.csv \
  "$BUNDLE_DIR/validation/legacy-candidate-runs.csv"
copy_file build/legacy-candidate-ab/summary.csv \
  "$BUNDLE_DIR/validation/legacy-candidate-summary.csv"
copy_file build/legacy-candidate-ab/metadata.json \
  "$BUNDLE_DIR/validation/legacy-candidate-metadata.json"
copy_file build/adversarial-differential/comparison.csv \
  "$BUNDLE_DIR/validation/adversarial-differential-comparison.csv"
copy_file build/jel-full-reproduction/outputs/summary.json \
  "$BUNDLE_DIR/validation/jel-full-summary.json"
copy_file build/jel-full-reproduction/outputs/artifact-comparison.csv \
  "$BUNDLE_DIR/validation/jel-artifact-comparison.csv"
copy_file build/jel-full-reproduction/outputs/figure-label-audit.csv \
  "$BUNDLE_DIR/validation/jel-figure-label-audit.csv"
copy_file build/jel-full-reproduction/outputs/table7-display-audit.csv \
  "$BUNDLE_DIR/validation/table7-display-audit.csv"
copy_file build/jel-full-reproduction/outputs/stata-figure-semantic-audit.csv \
  "$BUNDLE_DIR/validation/jel-stata-figure-semantic-audit.csv"

(
  cd "$BUNDLE_DIR"
  find . -type f ! -name MANIFEST.sha256 -print0 \
    | sort -z \
    | xargs -0 shasum -a 256 > MANIFEST.sha256
)

(
  cd dist
  zip -qr "${BUNDLE_NAME}.zip" "$BUNDLE_NAME"
)

shasum -a 256 "$ZIP_PATH" | tee "${ZIP_PATH}.sha256"
