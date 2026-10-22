#!/usr/bin/env python3
"""Run with: python3 fish/ghcl_test.py. Uses only temporary repositories."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import quote


FUNCTIONS = Path(__file__).with_name("ghcl.fish").resolve()
REMOTE = "https://github.com/test/project.git"
PAGE = "https://github.com/test/project"


class GhclTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ghcl-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.env = dict(
            os.environ,
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_ALLOW_PROTOCOL="file",  # A missed rewrite must not use the network.
        )

    def fish(self, code, *args, cwd=None, env=None):
        script = 'source "$argv[1]"; set -e argv[1]\n' + code
        return subprocess.run(
            ["fish", "--no-config", "-c", script, str(FUNCTIONS), *map(str, args)],
            cwd=cwd or self.root,
            env=self.env | (env or {}),
            capture_output=True,
            text=True,
            timeout=15,
        )

    def git(self, directory, *args):
        return subprocess.run(
            ["git", "-C", str(directory), *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        ).stdout.strip()

    def repository(self, name="source"):
        directory = self.root / name
        directory.mkdir()
        self.git(directory, "init", "--quiet", "--initial-branch=main")
        self.git(directory, "config", "user.name", "Test")
        self.git(directory, "config", "user.email", "test@example.invalid")
        self.git(directory, "config", "commit.gpgsign", "false")
        (directory / "README.md").write_text("test\n")
        (directory / "dir").mkdir()
        (directory / "dir/file.txt").write_text("nested\n")
        (directory / "directory\n").mkdir()
        (directory / "directory\n/file.txt").write_text("newline directory\n")
        for filename in ["space #%.txt", "-dash", "trailing\n", "café.txt"]:
            (directory / filename).write_text("special name\n")
        (directory / "directory-link").symlink_to("dir")
        (directory / "dangling-link").symlink_to("missing")
        self.git(directory, "add", ".")
        self.git(directory, "commit", "--quiet", "-m", "Fixture")
        self.git(directory, "remote", "add", "origin", REMOTE)
        self.git(directory, "update-ref", "refs/remotes/origin/main", "HEAD")
        self.git(directory, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        self.git(directory, "config", "branch.main.remote", "origin")
        self.git(directory, "config", "branch.main.merge", "refs/heads/main")
        return directory

    def checkout(self, destination, source):
        calls = self.root / "git-calls"
        result = self.fish(
            '''function git
                printf '%s\\n' "$argv[1]" >> "$GHCL_TEST_GIT_CALLS"
                command git $argv
            end
            __ghcl_checkout $argv
            set -l result $status
            printf '%s' "$PWD"
            exit $result
            ''',
            REMOTE,
            destination,
            env={
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": f"url.{source}.insteadOf",
                "GIT_CONFIG_VALUE_0": REMOTE,
                "GHCL_TEST_GIT_CALLS": str(calls),
            },
        )
        return result, calls.read_text().splitlines() if calls.exists() else []

    def open_path(self, directory, *args):
        opened = self.root / "opened-url"
        opened.unlink(missing_ok=True)
        result = self.fish(
            '''function git
                if contains -- fetch $argv; or contains -- ls-remote $argv; or contains -- set-head $argv
                    printf 'Unexpected network/ref update\\n' >&2
                    return 99
                end
                command git $argv
            end
            function open
                printf '%s' "$argv[1]" > "$GHCL_TEST_OPENED"
            end
            gho $argv
            ''',
            *args,
            cwd=directory,
            env={"GHCL_TEST_OPENED": str(opened)},
        )
        return result, opened.read_text() if opened.exists() else None

    def test_supported_urls(self):
        cases = {
            "test/project": REMOTE,
            "test/project.git/": REMOTE,
            "github.com/test/project": REMOTE,
            "https://github.com/test/project/blob/main/file?plain=1#L2": REMOTE,
            "HTTP://GITHUB.COM/test/project/": REMOTE,
            "https://github.com:443/test/project": "https://github.com:443/test/project.git",
            "https://github.com:8443/test/project": "https://github.com:8443/test/project.git",
            "git@github.com:test/project.git": "git@github.com:test/project.git",
            "ssh://git@github.com:22/test/project.git": "ssh://git@github.com:22/test/project.git",
            "ssh://git@GitHub.com:00022/test/project": "ssh://git@github.com:22/test/project.git",
            "ssh://git@ssh.github.com:443/test/project": "ssh://git@ssh.github.com:443/test/project.git",
            "git://github.com/test/project.git": REMOTE,
            "git://github.com:9418/test/project.git": REMOTE,
            "https://github.com/%74est/%70roject": REMOTE,
        }
        for url, remote in cases.items():
            with self.subTest(url=url):
                result = self.fish("parse_ghurl $argv", url)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ["test", "project", remote])
                self.assertEqual(result.stderr, "")

    def test_rejected_urls(self):
        cases = [
            "", "test", "test/", "/test/project", "test/project/extra",
            "test/.", "test/..", "test/...git", "test/%2e%2e", "test/%2fproject",
            "test/bad%00name", "test/bad%0aname", "test/bad%7fname", "test/bad%",
            "test/pro ject", "test/project\n", "test/\x1bproject",
            "https://example.com/test/project", "https://github.com.evil/test/project",
            "https://token@github.com/test/project", "ssh://other@github.com/test/project",
            "https://ssh.github.com/test/project", "https://github.com/test",
            "https://github.com:0/test/project", "https://github.com:65536/test/project",
            "https://github.com:abc/test/project", "https://github.com:/test/project",
            "ssh://git@github.com:22/test/project/extra", "git://github.com:9999/test/project",
            "https://github.com/test/project/../../other/repo",
            "https://github.com/test/project/%2e%2e/%2E./other/repo",
        ]
        for url in cases:
            with self.subTest(url=url):
                result = self.fish("parse_ghurl $argv", url)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertTrue(result.stderr)

    def test_argument_counts_and_public_destination(self):
        for function in ["parse_ghurl", "ghcl"]:
            for args in [(), ("test/project", "extra")]:
                with self.subTest(function=function, args=args):
                    result = self.fish(f"{function} $argv", *args)
                    self.assertNotEqual(result.returncode, 0)
        result = self.fish(
            "functions -q __ghcl_checkout; or exit 99\n"
            "function __ghcl_checkout; printf '%s\\0' $argv; end\nghcl $argv",
            "test/project",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split("\0")[:-1], [REMOTE, f"{os.environ['HOME']}/code/test/project"])

    def test_clone_then_reuse_without_another_network_operation(self):
        source = self.repository()
        destination = self.root / "checkouts/project"
        first, _ = self.checkout(destination, source)
        second, calls = self.checkout(destination, source)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, str(destination))
        self.assertEqual(calls.count("clone"), 1)
        self.assertNotIn("ls-remote", calls)
        self.assertTrue((destination / "README.md").is_file())

    def test_existing_empty_destination_can_be_cloned(self):
        source = self.repository()
        destination = self.root / "empty"
        destination.mkdir()
        result, _ = self.checkout(destination, source)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_existing_worktree_is_reused(self):
        source = self.repository()
        destination = self.root / "worktree"
        self.git(source, "worktree", "add", "--quiet", "--detach", str(destination))
        self.assertTrue((destination / ".git").is_file())
        result, calls = self.checkout(destination, source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(destination))
        self.assertNotIn("clone", calls)

    def test_symlinked_checkout_is_reused(self):
        source = self.repository()
        destination = self.root / "checkout-link"
        destination.symlink_to(source, target_is_directory=True)
        result, calls = self.checkout(destination, source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout).resolve(), source)
        self.assertNotIn("clone", calls)

    def test_failed_checkout_preserves_directory_and_contents(self):
        source = self.repository()
        for name in ["nonempty", "invalid-git"]:
            with self.subTest(destination=name):
                destination = self.root / name
                destination.mkdir()
                sentinel = destination / "keep"
                sentinel.write_text("untouched")
                if name == "invalid-git":
                    (destination / ".git").mkdir()
                result, _ = self.checkout(destination, source)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, str(self.root))
                self.assertEqual(sentinel.read_text(), "untouched")

    def test_clone_failure_preserves_status_and_cwd(self):
        result, _ = self.checkout(self.root / "failed", self.root / "missing-source")
        self.assertEqual(result.returncode, 128, result.stderr)
        self.assertEqual(result.stdout, str(self.root))

    def test_parent_creation_failure_does_not_clone(self):
        source = self.repository()
        blocker = self.root / "not-a-directory"
        blocker.write_text("untouched")
        result, calls = self.checkout(blocker / "project", source)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, str(self.root))
        self.assertNotIn("clone", calls)
        self.assertEqual(blocker.read_text(), "untouched")

    def test_gho_files_directories_and_symlinks(self):
        directory = self.repository()
        cases = [("README.md", "blob"), ("dir", "tree"), ("directory-link", "blob"), ("dangling-link", "blob")]
        for target, kind in cases:
            with self.subTest(target=target):
                result, opened = self.open_path(directory, target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(opened, f"{PAGE}/{kind}/main/{target}")

    def test_gho_special_filenames(self):
        directory = self.repository()
        for target in ["space #%.txt", "-dash", "trailing\n", "café.txt"]:
            with self.subTest(target=target):
                result, opened = self.open_path(directory, target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(opened, f"{PAGE}/blob/main/{quote(target, safe='/')}")
        result, opened = self.open_path(directory, "directory\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/tree/main/directory%0A")

    def test_gho_uses_the_committed_object_type(self):
        directory = self.repository()
        (directory / "dir/file.txt").unlink()
        (directory / "dir").rmdir()
        (directory / "dir").write_text("locally replaced directory")
        result, opened = self.open_path(directory, "dir")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/tree/main/dir")

        (directory / "README.md").unlink()
        (directory / "README.md").mkdir()
        result, opened = self.open_path(directory, "README.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/blob/main/README.md")

    def test_gho_root_uses_cached_default_without_mutating_refs(self):
        directory = self.repository()
        result, opened = self.open_path(directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, PAGE)
        self.git(directory, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        before = self.git(directory, "for-each-ref", "--format=%(refname) %(objectname)")
        result, opened = self.open_path(directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/tree/main")
        self.assertEqual(self.git(directory, "for-each-ref", "--format=%(refname) %(objectname)"), before)

    def test_gho_detached_head_uses_commit_permalink(self):
        directory = self.repository()
        commit = self.git(directory, "rev-parse", "HEAD")
        self.git(directory, "checkout", "--quiet", "--detach")
        result, opened = self.open_path(directory, "README.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/blob/{commit}/README.md")

    def test_gho_can_use_a_sole_non_origin_remote(self):
        directory = self.repository()
        self.git(directory, "remote", "rename", "origin", "upstream")
        self.git(directory, "config", "--remove-section", "branch.main")
        commit = self.git(directory, "rev-parse", "HEAD")
        result, opened = self.open_path(directory, "README.md")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(opened, f"{PAGE}/blob/{commit}/README.md")

    def test_gho_reports_ambiguous_remotes(self):
        directory = self.repository()
        self.git(directory, "remote", "rename", "origin", "first")
        self.git(directory, "config", "--remove-section", "branch.main")
        self.git(directory, "remote", "add", "second", "https://github.com/test/other.git")
        result, opened = self.open_path(directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(opened)
        self.assertIn("tracking remote", result.stderr)

    def test_gho_rejects_a_repository_without_commits(self):
        directory = self.root / "unborn"
        directory.mkdir()
        self.git(directory, "init", "--quiet", "--initial-branch=main")
        result, opened = self.open_path(directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(opened)
        self.assertIn("no commits", result.stderr)

    def test_gho_rejects_untracked_and_missing_paths(self):
        directory = self.repository()
        (directory / "untracked").write_text("local only")
        for target in ["untracked", "missing"]:
            with self.subTest(target=target):
                result, opened = self.open_path(directory, target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(opened)


if __name__ == "__main__":
    unittest.main(verbosity=2)
