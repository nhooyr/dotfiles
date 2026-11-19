"""Photo uploads with mocked gh and pbc; no network or system clipboard changes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(os.environ.get("GITHUB_FISH_TEST_SOURCE", Path(__file__).resolve().parents[1] / "github.fish"))
FISH = shutil.which("fish")
UPLOAD = "https://uploads.github.com/user-attachments/assets"
URL = "https://github.com/user-attachments/assets/example-image"


@unittest.skipUnless(FISH, "Fish is required")
class GitHubUploadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="github-upload-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        self.clipboard = self.root / "clipboard"
        self.photo = self.root / "photo.png"
        self.photo.write_bytes(b"\x89PNG\r\n\x1a\n\x00photo bytes\xff")
        self.env = dict(os.environ)
        self.env.update(
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"),
            XDG_CACHE_HOME=str(self.root / "cache"),
            TEST_CALL_LOG=str(self.log),
            TEST_CLIPBOARD=str(self.clipboard),
            TEST_UPLOAD_URL=URL,
        )
        program = r'''import json, os, pathlib, sys
kind = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {"kind": kind, "args": args, "cwd": os.getcwd()}
if kind == "gh" and "--input" in args:
    entry["bytes"] = pathlib.Path(args[args.index("--input") + 1]).read_bytes().hex()
if kind == "pbc":
    data = sys.stdin.buffer.read()
    entry["text"] = data.decode()
with open(os.environ["TEST_CALL_LOG"], "a") as log:
    log.write(json.dumps(entry) + "\n")
if kind == "pbc":
    if os.environ.get("TEST_FAIL") == "clipboard":
        sys.exit(19)
    pathlib.Path(os.environ["TEST_CLIPBOARD"]).write_bytes(data)
    sys.stdout.buffer.write(data)
elif args == ["api", "repos/{owner}/{repo}", "--jq", ".id, .html_url"]:
    if os.environ.get("TEST_FAIL") == "metadata":
        sys.exit(23)
    print(os.environ.get("TEST_REPOSITORY", "123\nhttps://github.com/example/project"))
elif "https://uploads.github.com/user-attachments/assets" in args:
    if os.environ.get("TEST_FAIL") == "upload":
        sys.exit(29)
    print(os.environ["TEST_UPLOAD_URL"])
else:
    sys.exit("unexpected gh invocation")
'''
        for name in ("gh", "pbc"):
            target = self.bin / name
            target.write_text("#!" + sys.executable + "\n" + program)
            target.chmod(0o755)

    def run_upload(self, *args, **environment):
        self.log.unlink(missing_ok=True)
        self.clipboard.write_text("previous clipboard")
        return subprocess.run(
            [FISH, "--no-config", "-c", 'source "$argv[1]"; ghss $argv[2..]', str(SOURCE), *map(str, args)],
            cwd=self.root,
            env=dict(self.env, **environment),
            text=True,
            capture_output=True,
        )

    def calls(self, kind=None):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [call for call in calls if kind is None or call["kind"] == kind]

    def test_supported_formats_preserve_bytes_and_quote_paths(self):
        for name, content_type in (
            ("photo.png", "image/png"),
            ("photo with 'quotes' [x] #$().JPG", "image/jpeg"),
            ("-photo.jpeg", "image/jpeg"),
        ):
            with self.subTest(name=name):
                photo = self.root / name
                photo.write_bytes(self.photo.read_bytes())
                result = self.run_upload("--", name)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"![Photo]({URL})\n")
                self.assertEqual(self.clipboard.read_text(), result.stdout)
                metadata, upload = self.calls("gh")
                self.assertEqual(metadata["cwd"], str(self.root))
                args = upload["args"]
                self.assertIn(UPLOAD, args)
                self.assertEqual(args[args.index("--input") + 1], str(photo))
                self.assertEqual(args[args.index("--method") + 1], "POST")
                self.assertEqual(upload["bytes"], photo.read_bytes().hex())
                for value in (
                    "repository_id=123", f"name={name}", f"content_type={content_type}",
                    f"Content-Length: {photo.stat().st_size}",
                    "Content-Type: application/octet-stream", "Accept: application/vnd.github+json",
                ):
                    self.assertIn(value, args)
                self.assertEqual(len(self.calls("pbc")), 1)

    def test_help_has_no_side_effects(self):
        result = self.run_upload("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage: ghss PHOTO", result.stdout)
        self.assertEqual(self.calls(), [])

    def test_invalid_inputs_never_reach_github(self):
        empty = self.root / "empty.png"
        empty.touch()
        wrong_type = self.root / "photo.gif"
        wrong_type.write_bytes(self.photo.read_bytes())
        large = self.root / "large.jpg"
        with large.open("wb") as file:
            file.truncate(10485761)
        for args in ((), ("missing.png",), (self.root,), (empty,), (wrong_type,), (large,), (self.photo, self.photo)):
            with self.subTest(args=args):
                result = self.run_upload(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])
                self.assertEqual(self.clipboard.read_text(), "previous clipboard")

    def test_github_failures_leave_clipboard_unchanged(self):
        for failure, code, requests in (("metadata", 23, 1), ("upload", 29, 2)):
            with self.subTest(failure=failure):
                result = self.run_upload(self.photo, TEST_FAIL=failure)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertEqual(len(self.calls("gh")), requests)
                self.assertEqual(self.calls("pbc"), [])
                self.assertEqual(self.clipboard.read_text(), "previous clipboard")

    def test_invalid_repository_never_uploads(self):
        for repository in ("", "null\nhttps://github.com/example/project", "123\nhttps://enterprise.example/example/project"):
            with self.subTest(repository=repository):
                result = self.run_upload(self.photo, TEST_REPOSITORY=repository)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.calls("gh")), 1)
                self.assertEqual(self.calls("pbc"), [])

    def test_missing_upload_url_leaves_clipboard_unchanged(self):
        result = self.run_upload(self.photo, TEST_UPLOAD_URL="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no image URL", result.stderr)
        self.assertEqual(self.calls("pbc"), [])
        self.assertEqual(self.clipboard.read_text(), "previous clipboard")

    def test_clipboard_failure_preserves_uploaded_url_in_error(self):
        result = self.run_upload(self.photo, TEST_FAIL="clipboard")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"![Photo]({URL})", result.stderr)
        self.assertEqual(len(self.calls("gh")), 2)
        self.assertEqual(len(self.calls("pbc")), 1)
        self.assertEqual(self.clipboard.read_text(), "previous clipboard")
