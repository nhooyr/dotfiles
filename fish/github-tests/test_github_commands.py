"""Public ghe/gho regressions; all GitHub traffic stays in temporary repos.

Run with: python3 -m unittest discover -s fish/github-tests -p 'test_github_commands.py'
Requires fish and Git. Browser, editor, and gh invocations are recorded mocks.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "github.fish"
FISH = shutil.which("fish")
GIT = shutil.which("git")


def fish_quote(value):
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"


if not FISH or not GIT:
    raise RuntimeError("Fish and Git are required to run the regression suite")


class GitHubCommandsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="github-commands-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.sandbox = self.root / "sandbox"
        self.sandbox.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        self.remote = self.root / "remote.git"
        self.seed = self.root / "seed"
        self.checkout = self.sandbox / "code" / "test-owner" / "test-repo"
        self.url = "https://github.com/test-owner/test-repo"
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        self.env.update(
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_DATA_HOME=str(self.root / "data"),
            XDG_CACHE_HOME=str(self.root / "cache"),
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_TERMINAL_PROMPT="0",
            GIT_ALLOW_PROTOCOL="file",
            GIT_EDITOR="true",
            GIT_PAGER="cat",
            PAGER="cat",
            TEST_REAL_GIT=GIT,
            TEST_CALL_LOG=str(self.log),
            TEST_REMOTE=str(self.remote),
            TEST_GH_RESPONSES="{}",
            TEST_OFFLINE="",
            TEST_CLONE_FAILURE="",
        )
        self._make_mocks()
        self.env["PATH"] = str(self.bin) + os.pathsep + os.environ["PATH"]
        self.env["EDITOR"] = str(self.bin / "editor")
        self.git(None, "init", "--bare", "--initial-branch=main", self.remote)
        self.git(None, "init", "--initial-branch=main", self.seed)
        self.configure_identity(self.seed)
        (self.seed / "dir").mkdir()
        (self.seed / "file.txt").write_text("first\nsecond\nthird\nfourth\n")
        (self.seed / "dir" / "nested.txt").write_text("nested\n")
        (self.seed / "a b#.txt").write_text("escaped name\n")
        (self.seed / ".gitignore").write_text("ignored.txt\n")
        (self.seed / "linked.txt").symlink_to("file.txt")
        (self.seed / "broken.txt").symlink_to("missing.txt")
        self.git(self.seed, "add", "-A")
        self.git(self.seed, "commit", "-qm", "initial")
        self.initial = self.git(self.seed, "rev-parse", "HEAD").stdout.strip()
        self.git(self.seed, "tag", "v1")
        self.git(self.seed, "remote", "add", "origin", self.remote)
        self.publish("main", "refs/tags/v1")
        self.checkout.parent.mkdir(parents=True)
        self.git(None, "clone", self.remote, self.checkout)
        self.configure_identity(self.checkout)
        self.git(self.checkout, "remote", "set-url", "origin", self.url + ".git")

    def _make_mocks(self):
        program = r'''import json, os, pathlib, subprocess, sys
kind = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {"kind": kind, "args": args}
if kind == "git":
    i = 0
    while i < len(args):
        if args[i] in ("-C", "-c", "--git-dir", "--work-tree"):
            i += 2
        elif args[i].startswith("-"):
            i += 1
        else:
            break
    command = args[i] if i < len(args) else ""
    entry["command"] = command
with open(os.environ["TEST_CALL_LOG"], "a") as log:
    log.write(json.dumps(entry) + "\n")
if kind == "git":
    if command == "push":
        sys.exit("the command under test must never push")
    if command == "clone" and os.environ.get("TEST_CLONE_FAILURE"):
        if os.environ["TEST_CLONE_FAILURE"] == "nonempty":
            sibling = pathlib.Path(args[-1]).parent / "unrelated.txt"
            sibling.write_text("keep unrelated file\n")
        sys.exit(37)
    if command in ("clone", "fetch", "ls-remote"):
        if os.environ.get("TEST_OFFLINE"):
            sys.exit("fixture is offline")
        j = i + 1
        value_options = {"-b", "--branch", "--depth", "--deepen", "--filter", "-c", "--config",
                         "-o", "--origin", "--upload-pack", "--exec", "--server-option",
                         "--shallow-since", "--shallow-exclude", "--reference", "--separate-git-dir"}
        while j < len(args):
            if args[j] == "--":
                j += 1
                break
            if args[j] in value_options:
                j += 2
            elif args[j].startswith("-"):
                j += 1
            else:
                break
        if j >= len(args):
            sys.exit("network command without a source")
        source = args[j]
        if ":" not in source and "/" not in source:
            query = subprocess.run(
                [os.environ["TEST_REAL_GIT"], *args[:i], "remote", "get-url", "--", source],
                text=True, capture_output=True, check=True)
            source = query.stdout.strip()
        allowed = {
            "https://github.com/test-owner/test-repo.git",
            "http://github.com/test-owner/test-repo.git",
            "git@github.com:test-owner/test-repo.git",
            "ssh://git@github.com:22/test-owner/test-repo.git",
            "ssh://git@ssh.github.com:443/test-owner/test-repo.git",
        }
        if source not in allowed:
            sys.exit("unmapped remote blocked: " + source)
        rule = "url." + pathlib.Path(os.environ["TEST_REMOTE"]).as_uri() + ".insteadOf=" + source
        args = ["-c", rule, *args]
    sys.exit(subprocess.call([os.environ["TEST_REAL_GIT"], *args]))
elif kind == "gh":
    endpoint = next((arg for arg in args if arg.startswith("repos/")), "")
    response = json.loads(os.environ["TEST_GH_RESPONSES"]).get(endpoint)
    if response is None:
        sys.exit("unmapped gh request: " + endpoint)
    print(response)
elif kind not in ("editor", "open", "dispatch"):
    sys.exit("unexpected mock executable")
'''
        for name in ("git", "gh", "open", "editor", "dispatch"):
            target = self.bin / name
            target.write_text("#!" + sys.executable + "\n" + program)
            target.chmod(0o755)

    def git(self, directory, *args, check=True):
        command = [GIT]
        if directory is not None:
            command += ["-C", str(directory)]
        command += [str(arg) for arg in args]
        return subprocess.run(
            command, env=self.env, text=True, capture_output=True, check=check
        )

    def configure_identity(self, directory):
        self.git(directory, "config", "user.name", "Regression Test")
        self.git(directory, "config", "user.email", "test@example.invalid")
        self.git(directory, "config", "commit.gpgsign", "false")

    def publish(self, *refs):
        self.git(self.seed, "push", "--quiet", "origin", *refs)

    def seed_commit(self, files, branch="main", create=False):
        args = ["switch", "--quiet"]
        if create:
            args += ["--create", branch, "main"]
        else:
            args += [branch]
        self.git(self.seed, *args)
        for name, content in files.items():
            target = self.seed / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
            self.git(self.seed, "add", "--force", "--", name)
        self.git(self.seed, "commit", "--quiet", "-m", "fixture update")
        revision = self.git(self.seed, "rev-parse", "HEAD").stdout.strip()
        self.publish(branch)
        return revision

    def fetch_fixture(self):
        rule = "url." + self.remote.as_uri() + ".insteadOf=" + self.url + ".git"
        self.git(self.checkout, "-c", rule, "fetch", "--quiet", "origin")

    def calls(self, kind=None):
        entries = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [entry for entry in entries if kind is None or entry["kind"] == kind]

    def clear_calls(self):
        self.log.unlink(missing_ok=True)

    def network_calls(self):
        return [entry for entry in self.calls("git") if entry["command"] in ("clone", "fetch", "ls-remote")]

    def run_fish(self, command, *args, cwd=None, offline=False, editor=None, responses=None, positions=("", "", "", "")):
        self.clear_calls()
        env = self.env.copy()
        env["TEST_OFFLINE"] = "1" if offline else ""
        if editor is not None:
            env["EDITOR"] = editor
        if responses is not None:
            env["TEST_GH_RESPONSES"] = json.dumps(responses)
        script = "source " + fish_quote(SOURCE) + "\n"
        if command == "ghe":
            # Exercise real parsing and checkout without redirecting system HOME.
            # The public ghe destination/anchor dispatch is tested separately.
            self.assertEqual(len(args), 1)
            script += "set -lx 0 ghe\nset -l parsed (__gh_parse " + fish_quote(args[0]) + ")\n"
            script += "if test (count $parsed) -eq 3\n"
            script += '__ghe_checkout "$parsed[3]" ' + fish_quote(self.checkout)
            script += ' "$parsed[2]" ' + " ".join(fish_quote(value) for value in positions)
            script += "\nelse\nfalse\nend\n"
        else:
            if command == "ghe_dispatch":
                script += "function __ghe_checkout\ncommand dispatch $argv\nend\n"
                command = "ghe"
            script += command + " " + " ".join(fish_quote(arg) for arg in args) + "\n"
        script += 'set -l result $status\nprintf "\\x1e%s" "$PWD"\nexit $result\n'
        result = subprocess.run(
            [FISH, "--no-config", "-c", script],
            cwd=cwd or self.sandbox,
            env=env,
            text=True,
            capture_output=True,
            timeout=20,
        )
        result.stdout, marker, result.directory = result.stdout.rpartition("\x1e")
        self.assertTrue(marker, result.stderr)
        return result

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def head(self):
        return self.git(self.checkout, "rev-parse", "HEAD").stdout.strip()

    def test_supported_transports_open_and_enter_the_same_repository(self):
        inputs = [
            "test-owner/test-repo",
            self.url + ".git",
            "https://github.com:443/test-owner/test-repo",
            "http://github.com:80/test-owner/test-repo",
            "github.com:443/test-owner/test-repo",
            "git@github.com:test-owner/test-repo.git",
            "ssh://git@github.com:22/test-owner/test-repo.git",
            "ssh://git@ssh.github.com:443/test-owner/test-repo.git",
        ]
        for value in inputs:
            with self.subTest(value=value):
                result = self.run_fish("gho", value)
                self.assert_success(result)
                self.assertEqual(self.calls("open")[0]["args"], [self.url])
                result = self.run_fish("ghe", value, offline=True)
                self.assert_success(result)
                self.assertEqual(result.directory, str(self.checkout))
                self.assertEqual(self.network_calls(), [])

    def test_direct_url_preserves_query_and_fragment(self):
        value = self.url + "/blob/main/a%20b%23.txt?plain=1#L2-L4"
        result = self.run_fish("gho", value)
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], [value])
        self.assertEqual(self.network_calls(), [])

    def test_rejects_traversal_and_controls_without_side_effects(self):
        for suffix in ("blob/main/%2e%2e/escape", "blob/main/a%0ab", "blob/main/a\nb"):
            for command in ("ghe", "gho"):
                with self.subTest(command=command, suffix=suffix):
                    result = self.run_fish(command, self.url + "/" + suffix)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.network_calls(), [])
                    self.assertEqual(self.calls("open") + self.calls("editor"), [])

    def test_local_default_root_and_escaped_file_urls(self):
        result = self.run_fish("gho", cwd=self.checkout)
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], [self.url])
        result = self.run_fish("gho", self.checkout / "a b#.txt")
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], [self.url + "/blob/main/a%20b%23.txt"])

    def test_gho_roots_open_the_homepage_or_branch_without_pr_detection(self):
        for branch, expected in (("main", self.url), ("topic", self.url + "/tree/topic")):
            if branch == "topic":
                self.git(self.checkout, "update-ref", "refs/remotes/origin/topic", self.initial)
                self.git(self.checkout, "switch", "--quiet", "--create", "topic", "--track", "origin/topic")
            for arguments, cwd in (((), self.checkout), ((self.checkout,), self.sandbox)):
                with self.subTest(branch=branch, arguments=arguments):
                    result = self.run_fish("gho", *arguments, cwd=cwd, offline=True)

                    self.assert_success(result)
                    self.assertEqual(result.stdout.strip(), expected)
                    self.assertEqual(self.calls("open")[0]["args"], [expected])
                    self.assertEqual(result.directory, str(cwd))
                    self.assertEqual(self.calls("gh"), [])
                    self.assertEqual(self.network_calls(), [])

    def test_local_ahead_branch_uses_remote_paths_and_rejects_new_paths(self):
        (self.checkout / "file.txt").write_text("local update\n")
        (self.checkout / "new-local.txt").write_text("not pushed\n")
        self.git(self.checkout, "add", "-A")
        self.git(self.checkout, "commit", "-qm", "local commit")
        result = self.run_fish("gho", self.checkout / "file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], [self.url + "/blob/main/file.txt"])
        result = self.run_fish("gho", self.checkout / "new-local.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cached remote branch", result.stderr)
        self.assertEqual(self.calls("open"), [])

    def test_unpushed_new_branch_has_a_clear_error(self):
        self.git(self.checkout, "switch", "--quiet", "--create", "unpublished")
        result = self.run_fish("gho", self.checkout, offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not been pushed or fetched", result.stderr)
        self.assertEqual(self.calls("open"), [])

    def test_tracked_symlinks_open_the_link_and_installed_links_resolve(self):
        for name in ("linked.txt", "broken.txt"):
            with self.subTest(name=name):
                result = self.run_fish("gho", self.checkout / name)
                self.assert_success(result)
                self.assertEqual(self.calls("open")[0]["args"], [self.url + "/blob/main/" + name])
        installed = self.sandbox / "installed.txt"
        installed.symlink_to(self.checkout / "file.txt")
        result = self.run_fish("gho", installed)
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], [self.url + "/blob/main/file.txt"])

    def test_submodule_root_opens_the_submodule_repository(self):
        sub = self.checkout / "submodule"
        self.git(self.checkout, "submodule", "add", "--quiet", self.remote, "submodule")
        self.git(sub, "remote", "set-url", "origin", "https://github.com/test-owner/submodule.git")
        self.git(sub, "switch", "--quiet", "main")
        self.git(sub, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        result = self.run_fish("gho", sub, offline=True)
        self.assert_success(result)
        self.assertEqual(self.calls("open")[0]["args"], ["https://github.com/test-owner/submodule"])

    def test_existing_file_and_directory_open_offline_without_network(self):
        result = self.run_fish("ghe", self.url + "/blob/main/file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(self.calls("editor")[0]["args"], [str(self.checkout / "file.txt")])
        self.assertEqual(self.network_calls(), [])
        result = self.run_fish("ghe", self.url + "/tree/main/dir", offline=True)
        self.assert_success(result)
        self.assertEqual(result.directory, str(self.checkout / "dir"))
        self.assertEqual(self.calls("editor"), [])
        self.assertEqual(self.network_calls(), [])

    def test_new_clone_is_not_fetched_again(self):
        shutil.rmtree(self.checkout)
        result = self.run_fish("ghe", self.url)
        self.assert_success(result)
        self.assertEqual(result.directory, str(self.checkout))
        self.assertEqual([call["command"] for call in self.network_calls()], ["clone"])
        self.assertEqual(self.git(self.checkout, "remote", "get-url", "origin").stdout.strip(), self.url + ".git")

    def assert_clone_failed_without_changing_directory(self, result):
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertEqual(result.directory, str(self.sandbox))
        self.assertFalse(self.checkout.exists())
        self.assertEqual(self.calls("editor"), [])
        self.assertEqual([call["command"] for call in self.network_calls()], ["clone"])

    def test_failed_clone_removes_new_empty_organization_directory(self):
        shutil.rmtree(self.checkout.parent)
        self.env["TEST_CLONE_FAILURE"] = "empty"
        result = self.run_fish("ghe", self.url)
        self.assert_clone_failed_without_changing_directory(result)
        self.assertFalse(self.checkout.parent.exists())
        self.assertTrue(self.checkout.parent.parent.is_dir())

    def test_failed_clone_retains_preexisting_empty_organization_directory(self):
        shutil.rmtree(self.checkout)
        self.env["TEST_CLONE_FAILURE"] = "empty"
        result = self.run_fish("ghe", self.url)
        self.assert_clone_failed_without_changing_directory(result)
        self.assertTrue(self.checkout.parent.is_dir())
        self.assertEqual(list(self.checkout.parent.iterdir()), [])

    def test_organization_creation_race_preserves_the_other_directory(self):
        shutil.rmtree(self.checkout.parent)
        self.env["TEST_CLONE_FAILURE"] = "empty"
        self.env["TEST_ORG_DIR"] = str(self.checkout.parent)
        self.env["TEST_REAL_MKDIR"] = shutil.which("mkdir")
        program = '''import os, pathlib, sys
if pathlib.Path(sys.argv[-1]) == pathlib.Path(os.environ["TEST_ORG_DIR"]):
    # Another process creates the organization after ghe's directory check.
    pathlib.Path(sys.argv[-1]).mkdir(parents=True, exist_ok=True)
os.execv(os.environ["TEST_REAL_MKDIR"], [os.environ["TEST_REAL_MKDIR"], *sys.argv[1:]])
'''
        mkdir = self.bin / "mkdir"
        mkdir.write_text("#!" + sys.executable + "\n" + program)
        mkdir.chmod(0o755)

        result = self.run_fish("ghe", self.url)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.directory, str(self.sandbox))
        self.assertTrue(self.checkout.parent.is_dir())
        self.assertEqual(list(self.checkout.parent.iterdir()), [])

    def test_failed_clone_retains_new_nonempty_organization_and_clone_exit_status(self):
        shutil.rmtree(self.checkout.parent)
        self.env["TEST_CLONE_FAILURE"] = "nonempty"
        result = self.run_fish("ghe", self.url)
        self.assert_clone_failed_without_changing_directory(result)
        self.assertEqual((self.checkout.parent / "unrelated.txt").read_text(), "keep unrelated file\n")
        self.assertIn("rmdir:", result.stderr)
        self.assertIn(str(self.checkout.parent), result.stderr)

    def test_successful_clone_retains_new_organization_directory(self):
        shutil.rmtree(self.checkout.parent)
        result = self.run_fish("ghe", self.url)
        self.assert_success(result)
        self.assertTrue(self.checkout.parent.is_dir())
        self.assertTrue((self.checkout / ".git").is_dir())
        self.assertEqual(result.directory, str(self.checkout))
        self.assertEqual([call["command"] for call in self.network_calls()], ["clone"])

    def test_clean_missing_path_pulls_before_opening(self):
        revision = self.seed_commit({"new-upstream.txt": "upstream\n"})
        result = self.run_fish("ghe", self.url + "/blob/main/new-upstream.txt")
        self.assert_success(result)
        self.assertEqual(self.head(), revision)
        self.assertEqual((self.checkout / "new-upstream.txt").read_text(), "upstream\n")
        self.assertEqual(self.calls("editor")[0]["args"], [str(self.checkout / "new-upstream.txt")])
        self.assertEqual([call["command"] for call in self.network_calls()], ["fetch"])

    def test_dirty_missing_path_does_not_pull(self):
        self.seed_commit({"new-upstream.txt": "upstream\n"})
        (self.checkout / "file.txt").write_text("keep local edit\n")
        result = self.run_fish("ghe", self.url + "/blob/main/new-upstream.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.head(), self.initial)
        self.assertEqual((self.checkout / "file.txt").read_text(), "keep local edit\n")
        self.assertEqual(self.network_calls(), [])

    def test_dirty_checkout_keeps_current_branch_when_visiting_another_ref(self):
        self.seed_commit({"file.txt": "feature\n"}, branch="feature", create=True)
        self.fetch_fixture()
        (self.checkout / "file.txt").write_text("keep local edit\n")
        result = self.run_fish("ghe", self.url + "/tree/feature")
        self.assert_success(result)
        self.assertIn("keeping the current ref", result.stderr)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual((self.checkout / "file.txt").read_text(), "keep local edit\n")

    def test_dirty_existing_path_does_not_fetch_uncached_short_commit(self):
        revision = self.seed_commit({"file.txt": "upstream change\n"})
        self.assertNotEqual(self.git(self.checkout, "cat-file", "-e", revision, check=False).returncode, 0)
        (self.checkout / "file.txt").write_text("keep local edit\n")

        result = self.run_fish("ghe", self.url + "/blob/" + revision[:10] + "/file.txt")

        self.assert_success(result)
        self.assertIn("keeping the current ref", result.stderr)
        self.assertEqual(self.head(), self.initial)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual((self.checkout / "file.txt").read_text(), "keep local edit\n")
        self.assertEqual(self.calls("editor")[0]["args"], [str(self.checkout / "file.txt")])
        self.assertNotIn("fetch", [call["command"] for call in self.network_calls()])

    def test_ignored_file_is_not_overwritten_by_switch(self):
        self.seed_commit({"ignored.txt": "tracked upstream\n"}, branch="feature", create=True)
        self.fetch_fixture()
        (self.checkout / "ignored.txt").write_text("keep ignored file\n")
        result = self.run_fish("ghe", self.url + "/tree/feature")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.head(), self.initial)
        self.assertEqual((self.checkout / "ignored.txt").read_text(), "keep ignored file\n")

    def test_ignored_file_is_not_overwritten_by_pull(self):
        self.seed_commit({"ignored.txt": "tracked upstream\n", "new-upstream.txt": "upstream\n"})
        (self.checkout / "ignored.txt").write_text("keep ignored file\n")
        result = self.run_fish("ghe", self.url + "/blob/main/new-upstream.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.head(), self.initial)
        self.assertEqual((self.checkout / "ignored.txt").read_text(), "keep ignored file\n")
        self.assertFalse((self.checkout / "new-upstream.txt").exists())

    def test_missing_path_pull_does_not_merge_diverged_history(self):
        self.seed_commit({"new-upstream.txt": "upstream\n"})
        (self.checkout / "local.txt").write_text("local commit\n")
        self.git(self.checkout, "add", "local.txt")
        self.git(self.checkout, "commit", "-qm", "local divergence")
        before = self.head()
        result = self.run_fish("ghe", self.url + "/blob/main/new-upstream.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.head(), before)
        self.assertEqual((self.checkout / "local.txt").read_text(), "local commit\n")
        self.assertFalse((self.checkout / "new-upstream.txt").exists())

    def test_line_column_and_selection_arguments_reach_the_editor(self):
        cases = {
            ("2", "", "", ""): "+2",
            ("2", "3", "", ""): "+call cursor(2, 3)",
            ("2", "", "4", ""): "+set selection=inclusive | call cursor(2, 1) | execute 'normal! V' | call cursor(4, 1)",
            ("2", "2", "4", ""): "+set selection=inclusive | call cursor(2, 2) | execute 'normal! v' | call cursor(4, max([1, strlen(getline(4))]))",
            ("2", "", "4", "3"): "+set selection=inclusive | call cursor(2, 1) | execute 'normal! v' | call cursor(4, 3)",
        }
        editor = fish_quote(self.bin / "editor") + " --wait 'two words'"
        for positions, position in cases.items():
            with self.subTest(positions=positions):
                result = self.run_fish("ghe", self.url + "/blob/main/file.txt", editor=editor, positions=positions)
                self.assert_success(result)
                self.assertEqual(self.calls("editor")[0]["args"], ["--wait", "two words", position, str(self.checkout / "file.txt")])

    def test_public_ghe_dispatches_destination_and_normalized_anchors_without_writing(self):
        result = self.run_fish("ghe_dispatch", self.url + "/blob/main/file.txt#L002C03-L004C05")
        self.assert_success(result)
        expected_destination = Path.home() / "code" / "test-owner" / "test-repo"
        self.assertEqual(self.calls("dispatch")[0]["args"], [
            self.url + ".git", str(expected_destination), "blob/main/file.txt", "2", "3", "4", "5"
        ])
        self.assertEqual(self.network_calls(), [])
        self.assertEqual(self.calls("editor"), [])

    def test_raw_edit_release_and_archive_routes(self):
        cases = [
            (self.url + "/raw/main/file.txt", True, False),
            (self.url + "/edit/main/file.txt", True, False),
            ("https://raw.githubusercontent.com/test-owner/test-repo/main/file.txt", True, False),
            ("https://raw.githubusercontent.com/test-owner/test-repo/refs/heads/main/file.txt", True, False),
            ("https://raw.githubusercontent.com/test-owner/test-repo/refs/tags/v1/file.txt", True, True),
            (self.url + "/releases/tag/v1", False, True),
            (self.url + "/archive/refs/heads/main.zip", False, False),
            (self.url + "/archive/refs/tags/v1.tar.gz", False, True),
            (self.url + "/archive/" + self.initial + ".zip", False, True),
        ]
        for value, edit, detached in cases:
            with self.subTest(value=value):
                self.git(self.checkout, "switch", "--quiet", "main")
                result = self.run_fish("ghe", value, offline=True)
                self.assert_success(result)
                self.assertEqual(bool(self.calls("editor")), edit)
                self.assertEqual(self.head(), self.initial)
                branch = self.git(self.checkout, "branch", "--show-current").stdout.strip()
                self.assertEqual(branch, "" if detached else "main")
                self.assertEqual(self.network_calls(), [])

    def test_latest_release_uses_mocked_api_and_checks_out_its_tag(self):
        endpoint = "repos/test-owner/test-repo/releases/latest"
        result = self.run_fish("ghe", self.url + "/releases/latest", responses={endpoint: "v1"})
        self.assert_success(result)
        self.assertEqual(len(self.calls("gh")), 1)
        self.assertIn(endpoint, self.calls("gh")[0]["args"])
        self.assertEqual(self.head(), self.initial)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "")

    def test_pull_request_head_and_offline_cache(self):
        revision = self.seed_commit({"file.txt": "pull request\n"}, branch="feature", create=True)
        self.publish(revision + ":refs/pull/7/head")
        result = self.run_fish("ghe", self.url + "/pull/7")
        self.assert_success(result)
        self.assertEqual(self.head(), revision)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "")
        self.assertEqual([call["command"] for call in self.network_calls()], ["fetch"])
        result = self.run_fish("ghe", self.url + "/pull/7", offline=True)
        self.assert_success(result)
        self.assertEqual(self.head(), revision)

    def test_pull_request_files_uses_mocked_api_without_switching(self):
        revision = self.seed_commit({"file.txt": "pull request\n"}, branch="feature", create=True)
        self.fetch_fixture()
        endpoint = "repos/test-owner/test-repo/pulls/7"
        result = self.run_fish("ghe", self.url + "/pull/7/files", responses={endpoint: self.initial + "\n" + revision})
        self.assert_success(result)
        self.assertIn("+pull request", result.stdout)
        self.assertEqual(self.head(), self.initial)
        self.assertEqual(self.git(self.checkout, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual(self.network_calls(), [])


if __name__ == "__main__":
    unittest.main()
