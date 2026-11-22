"""Run isolated GitHub regression tests in parallel."""

import argparse
from contextlib import redirect_stderr, redirect_stdout
import io
from multiprocessing import Pool
import os
from pathlib import Path
import sys
import time
import unittest


def test_names(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from test_names(test)
        else:
            yield test.id()


def run_test(name):
    output = io.StringIO()
    with redirect_stdout(output), redirect_stderr(output):
        suite = unittest.defaultTestLoader.loadTestsFromName(name)
        result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    success = result.wasSuccessful()
    return result.testsRun, success, len(result.skipped), "" if success else output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-j", "--jobs", type=int,
        default=getattr(os, "process_cpu_count", os.cpu_count)() or 1,
        help="number of worker processes (default: available CPUs)",
    )
    parser.add_argument("tests", nargs="*", help="specific test identifiers (default: all tests)")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")

    loader = unittest.defaultTestLoader
    suite = loader.loadTestsFromNames(args.tests) if args.tests else loader.discover(Path(__file__).parent)
    if loader.errors:
        print("\n".join(loader.errors), file=sys.stderr)
        return 1
    names = list(test_names(suite))
    if not names:
        parser.error("no tests selected")

    jobs = min(args.jobs, len(names))
    print(f"Running {len(names)} tests with {jobs} workers", file=sys.stderr)
    started = time.monotonic()
    completed = skipped = 0
    failures = []
    try:
        with Pool(jobs) as pool:
            for count, success, skip_count, output in pool.imap_unordered(run_test, names):
                completed += count
                skipped += skip_count
                print("F" if not success else "s" if skip_count else ".", end="", file=sys.stderr, flush=True)
                if not success:
                    failures.append(output)
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130

    print(file=sys.stderr)
    for output in failures:
        print(output, file=sys.stderr)
    print(f"Ran {completed} tests in {time.monotonic() - started:.3f}s", file=sys.stderr)
    details = []
    if failures:
        details.append(f"failed tests={len(failures)}")
    if skipped:
        details.append(f"skipped={skipped}")
    summary = "FAILED" if failures else "OK"
    if details:
        summary += " (" + ", ".join(details) + ")"
    print(summary, file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
