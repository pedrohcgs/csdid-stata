"""Fresh, attributable Stata processes for the required benchmark gates."""

import math
import os
from pathlib import Path
import subprocess
import time


def stata_command():
    return os.environ.get("STATA_CMD") or "stata-mp"


def prepare_build(root):
    # Native test binaries belong in build/, outside the shipped manifest.
    env = dict(os.environ, CSDID_PLUGIN_OUTDIR=str(root / "build"))
    subprocess.run(["bash", "tools/plugin/build-bootstrap-plugin.sh", "auto"],
                   cwd=root, env=env, check=True)
    subprocess.run(["bash", "tools/release/build-package.sh"], cwd=root, check=True)


def scan_log(root, log):
    subprocess.run(["bash", str(root / "tools/release/check-stata-log-tail.sh"),
                    str(log)], cwd=root, check=True)


def run_stata(root, dofile):
    # Stata's batch basename ends at its first dot, including on 17 and 19.5.
    log = root / (Path(dofile).name.split(".", 1)[0] + ".log")
    log.unlink(missing_ok=True)
    subprocess.run([stata_command(), "-b", "do", str(dofile)], cwd=root, check=True)
    scan_log(root, log)


def write_driver(root, path, dofile, arguments):
    # CLI arguments change Stata's batch-log name. Embed them in a driver so
    # both Stata 17 and 19.5 produce the log named by this one do-file.
    values = [str(root / dofile), *(str(value) for value in arguments)]
    if any(any(char in value for char in ('"', '`', '$', '\n', '\r')) for value in values):
        raise ValueError("Stata benchmark paths/arguments cannot contain macro delimiters, quotes or line breaks")
    path.write_text("do " + " ".join('"' + value + '"' for value in values) + "\n")


def rss_kb(pid):
    result = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)],
                            capture_output=True, text=True, check=False)
    # The process may have exited between poll() and ps. That is an absent
    # observation, never a zero-memory observation that can pass a budget.
    if result.returncode != 0 or not result.stdout.strip():
        return None
    value = float(result.stdout.strip())
    if not math.isfinite(value) or value < 0:
        raise RuntimeError("ps returned an invalid resident-memory observation")
    return value if value > 0 else None


def measure_stata(root, stata, driver, log):
    batch = root / (driver.name.split(".", 1)[0] + ".log")
    batch.unlink(missing_ok=True)
    log.unlink(missing_ok=True)
    process = subprocess.Popen([stata, "-b", "do", str(driver)], cwd=root,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    peak_kb = 0.0
    samples = 0
    started = time.perf_counter()
    try:
        while True:
            running = process.poll() is None
            value = rss_kb(process.pid)
            if value is not None:
                samples += 1
                peak_kb = max(peak_kb, value)
            if not running:
                break
            time.sleep(0.002)
    except BaseException:
        process.kill()
        process.wait()
        raise
    elapsed = time.perf_counter() - started
    if process.returncode != 0:
        raise RuntimeError(f"Stata exited {process.returncode}; inspect {batch}")
    scan_log(root, batch)
    batch.replace(log)
    if samples == 0 or not math.isfinite(peak_kb) or peak_kb <= 0:
        raise RuntimeError("no positive resident-memory observation from ps; the memory gate cannot certify this run")
    if not math.isfinite(elapsed) or elapsed <= 0:
        raise RuntimeError("no positive elapsed-time observation")
    return elapsed, peak_kb / 1024.0, samples
