"""Git regressions; run with python3 -m unittest discover -s fish/github-tests.

Fixtures use real Git repositories and file transport. A small Git wrapper supplies
URL rewrites only for transport commands, so repository identity and refspec logic
still see GitHub URLs. Git permits no other transport, and user configuration,
credentials, editors, and browsers are never used.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(os.environ.get("GITHUB_FISH_TEST_SOURCE", Path(__file__).resolve().parents[1] / "github.fish"))
GIT = shutil.which("git")
FISH = shutil.which("fish")
URL = "https://github.com/example/project.git"

GIT_WRAPPER = r'''#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
index = 0
while index < len(args):
    arg = args[index]
    if arg in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"):
        index += 2
    elif arg.startswith("-"):
        index += 1
    else:
        break
command = args[index] if index < len(args) else ""
transport = command in ("fetch", "ls-remote", "clone", "pull", "push")
rewrites = []
if transport:
    with open(os.environ["GITHUB_TEST_TRANSPORT_LOG"], "a", encoding="utf-8") as log:
        log.write(json.dumps({"command": command, "args": args}) + "\n")
    if command == "push":
        sys.stderr.write("Tests must not push.\n")
        sys.exit(98)
    if os.environ.get("GITHUB_TEST_OFFLINE") == "1":
        sys.stderr.write("Fixture transport is offline.\n")
        sys.exit(99)
    for github_url, local_url in json.loads(os.environ["GITHUB_TEST_URLS"]).items():
        rewrites.extend(("-c", "url." + local_url + ".insteadOf=" + github_url))
real_git = os.environ["GITHUB_TEST_REAL_GIT"]
os.execve(real_git, [real_git, *rewrites, *args], os.environ)
'''


if not GIT or not FISH:
    raise RuntimeError("Fish and Git are required to run the regression suite")


class GithubRefsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-github-refs-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        wrapper = self.bin / "git"
        wrapper.write_text(GIT_WRAPPER, encoding="utf-8")
        wrapper.chmod(0o755)
        self.log = self.directory / "transport.jsonl"
        self.urls = {}
        self.counter = 0
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(
            PATH=str(self.bin) + os.pathsep + os.environ.get("PATH", os.defpath),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_SYSTEM=os.devnull,
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_TERMINAL_PROMPT="0",
            GIT_ALLOW_PROTOCOL="file",
            GITHUB_TEST_REAL_GIT=GIT,
            GITHUB_TEST_TRANSPORT_LOG=str(self.log),
            XDG_CONFIG_HOME=str(self.directory / "config"),
            XDG_DATA_HOME=str(self.directory / "data"),
            XDG_CACHE_HOME=str(self.directory / "cache"),
            LC_ALL="C",
        )
        self.source = self.new_repository("source")
        self.initial = self.commit(self.source, "initial\n")
        self.urls[URL] = self.source.as_uri()

    def git(self, repository, *args, check=True, input=None):
        result = subprocess.run(
            [GIT, "-C", str(repository), *args],
            env=self.env,
            input=input,
            text=True,
            capture_output=True,
            timeout=20,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def new_repository(self, name):
        self.counter += 1
        repository = self.directory / (name + str(self.counter))
        repository.mkdir()
        self.git(repository, "init", "--quiet", "--initial-branch=main", "--object-format=sha1")
        self.git(repository, "config", "user.name", "Dotfiles tests")
        self.git(repository, "config", "user.email", "dotfiles-tests@example.invalid")
        return repository

    def commit(self, repository, contents, filename="file.txt"):
        path = repository / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        self.git(repository, "add", "--", filename)
        self.git(repository, "commit", "--quiet", "--message", "Fixture change")
        return self.oid(repository)

    def empty_root_commit(self, repository, message):
        tree = self.git(repository, "hash-object", "-w", "-t", "tree", "--stdin", input="").stdout.strip()
        identity = "Dotfiles tests <dotfiles-tests@example.invalid> 0 +0000"
        text = "tree %s\nauthor %s\ncommitter %s\n\n%s\n" % (tree, identity, identity, message)
        return self.git(repository, "hash-object", "-w", "-t", "commit", "--stdin", input=text).stdout.strip()

    def colliding_hex_commit(self, repository, *, with_paths):
        if not with_paths:
            return self.empty_root_commit(repository, "hex branch 6984")
        blob = self.git(repository, "hash-object", "-w", "--stdin", input="unrelated file\n").stdout.strip()
        subtree = self.git(repository, "mktree", input="100644 blob %s\tfile.txt\n" % blob).stdout.strip()
        tree = self.git(repository, "mktree", input="100644 blob %s\tfile.txt\n040000 tree %s\tfix\n" % (blob, subtree)).stdout.strip()
        identity = "Dotfiles tests <dotfiles-tests@example.invalid> 0 +0000"
        # Fixed tree and message produce 20269db4..., with file.txt and fix/file.txt.
        text = "tree %s\nauthor %s\ncommitter %s\n\nhex path 35985\n" % (tree, identity, identity)
        return self.git(repository, "hash-object", "-w", "-t", "commit", "--stdin", input=text).stdout.strip()

    def oid(self, repository, ref="HEAD"):
        return self.git(repository, "rev-parse", "--verify", ref).stdout.strip()

    def clone(self, *, single_branch=False, depth=None, object_filter=None):
        self.counter += 1
        destination = self.directory / ("checkout" + str(self.counter))
        options = ["--quiet", "--no-tags"] if single_branch else ["--quiet"]
        if single_branch:
            options.extend(("--single-branch", "--branch=main"))
        if depth:
            options.append("--depth=" + str(depth))
        if object_filter:
            options.append("--filter=" + object_filter)
        self.git(self.directory, "clone", *options, self.source.as_uri(), str(destination))
        self.git(destination, "remote", "set-url", "origin", URL)
        self.git(destination, "config", "user.name", "Dotfiles tests")
        self.git(destination, "config", "user.email", "dotfiles-tests@example.invalid")
        return destination

    def empty_checkout(self):
        destination = self.new_repository("empty")
        self.git(destination, "remote", "add", "origin", URL)
        return destination

    def matching_remote(self, destination, name="aaa", tracking=None):
        tracking = tracking or "refs/remotes/" + name + "/main"
        self.git(destination, "remote", "add", name, URL)
        self.git(destination, "config", "--replace-all", "remote." + name + ".fetch",
                 "+refs/heads/main:" + tracking)
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                 "fetch", "--quiet", name)
        self.git(destination, "symbolic-ref", "refs/remotes/" + name + "/HEAD", tracking)
        return tracking

    def fish(self, body, *args, offline=False):
        self.log.write_text("", encoding="utf-8")
        env = self.env | {
            "GITHUB_TEST_URLS": json.dumps(self.urls),
            "GITHUB_TEST_OFFLINE": "1" if offline else "0",
            "EDITOR": "__test_editor",
        }
        script = '''source "$argv[1]"; or exit
set -e argv[1]
set -lx 0 test
function __test_editor
    return 0
end
function open
    return 0
end
''' + body
        result = subprocess.run(
            [FISH, "--no-config", "-c", script, str(SOURCE), *map(str, args)],
            cwd=self.directory,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.transport = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result

    def compare_ref(self, destination, ref, *, offline=False, url=URL):
        return self.fish(
            '__ghe_compare_ref "$argv[1]" "$argv[2]" "$argv[3]"',
            url, destination, ref, offline=offline,
        )

    def checkout(self, destination, tail, *, offline=False):
        return self.fish(
            '__ghe_checkout "$argv[1]" "$argv[2]" "$argv[3]" \'\' \'\' \'\' \'\'',
            URL, destination, tail, offline=offline,
        )

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_resolves(self, destination, ref, oid, *, offline=False):
        result = self.compare_ref(destination, ref, offline=offline)
        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), oid)
        if offline:
            self.assertTrue(self.transport, "Named comparison did not try to refresh")
            self.assertIn("cached", result.stderr)

    def test_remote_matching_handles_filters_multiple_urls_and_rewrites(self):
        other_url = "https://github.com/other/project.git"
        for configuration in ("promisor", "multiple_urls", "push_url", "rewrite"):
            with self.subTest(configuration=configuration):
                destination = self.clone()
                if configuration == "promisor":
                    self.git(destination, "config", "remote.origin.promisor", "true")
                    self.git(destination, "config", "remote.origin.partialclonefilter", "blob:none")
                elif configuration == "multiple_urls":
                    self.git(destination, "config", "--add", "remote.origin.url", other_url)
                elif configuration == "push_url":
                    self.git(destination, "config", "remote.origin.pushurl", other_url)
                else:
                    self.git(destination, "remote", "set-url", "origin", "gh-test:project.git")
                    self.git(destination, "config", "url.https://github.com/example/.insteadOf", "gh-test:")

                result = self.fish('__gh_remotes "$argv[1]" "$argv[2]"', URL, destination, offline=True)
                self.assert_success(result)
                self.assertEqual(result.stdout, "origin\n")
                self.assertEqual(self.transport, [])
                result = self.fish('__gh_remotes "$argv[1]" "$argv[2]"', other_url, destination, offline=True)
                self.assert_success(result)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.transport, [])

                if configuration == "promisor":
                    result = self.checkout(destination, "blob/main/file.txt", offline=True)
                    self.assert_success(result)
                    self.assertEqual(self.transport, [], "Existing partial-clone path attempted transport")

    def test_comparison_cache_handles_unicode_ref_without_filename_expansion(self):
        name = "feature/" + "修复" * 20
        self.git(self.source, "branch", name)
        destination = self.empty_checkout()
        self.assert_resolves(destination, name, self.initial)
        self.assert_resolves(destination, name, self.initial, offline=True)

    def test_comparison_cache_survives_ref_hierarchy_replacements(self):
        for namespace in ("heads", "tags"):
            for names in (("topic", "topic/fix"), ("topic/fix", "topic")):
                with self.subTest(namespace=namespace, names=names):
                    destination = self.empty_checkout()
                    for name in names:
                        source_ref = "refs/" + namespace + "/" + name
                        self.git(self.source, "update-ref", source_ref, self.initial)
                        ref = namespace + "/" + name
                        self.assert_resolves(destination, ref, self.initial)
                        self.assert_resolves(destination, ref, self.initial, offline=True)
                        self.git(self.source, "update-ref", "-d", source_ref)

    def test_preexisting_comparison_cache_formats_work_offline(self):
        for namespace in ("heads", "tags"):
            source_ref = "refs/" + namespace + "/Topic"
            for cache_format in ("hierarchical", "escaped", "hashed"):
                with self.subTest(namespace=namespace, cache_format=cache_format):
                    destination = self.empty_checkout()
                    self.git(destination, "fetch", "--quiet", "--no-tags", self.source.as_uri(), "main")
                    identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
                    key = {
                        "hierarchical": source_ref,
                        "escaped": "refs_2F_" + namespace + "_2F_Topic",
                        "hashed": "by-ref/" + self.git(destination, "hash-object", "--stdin", input=source_ref + "\n").stdout.strip(),
                    }[cache_format]
                    self.git(destination, "update-ref", "refs/gh/compare/" + identity + "/" + key, self.initial)
                    self.assert_resolves(destination, namespace + "/Topic", self.initial, offline=True)
                    self.assertNotEqual(self.compare_ref(destination, namespace + "/topic", offline=True).returncode, 0)

    def test_comparison_request_cannot_alias_another_cache_key(self):
        main_key = self.git(self.source, "hash-object", "--stdin", input="main\n").stdout.strip()
        for branch in ("by-ref/" + main_key, "refs_2F_heads_2F_main"):
            with self.subTest(branch=branch):
                self.git(self.source, "switch", "--quiet", "--create", branch, "main")
                tip = self.commit(self.source, branch + "\n")
                self.git(self.source, "switch", "--quiet", "main")
                destination = self.clone()
                self.assert_success(self.compare_ref(destination, "main"))
                identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
                # Keep an older escaped cache beside the current hashed main cache.
                self.git(destination, "update-ref", "refs/gh/compare/" + identity + "/refs_2F_heads_2F_main", self.initial)
                self.assertEqual(self.oid(destination, "refs/remotes/origin/" + branch), tip)

                result = self.compare_ref(destination, branch, offline=True)

                self.assert_success(result)
                self.assertEqual(result.stdout.strip(), tip)

    def test_fork_comparison_caches_are_repository_specific(self):
        destination = self.empty_checkout()
        expected = {}
        for owner, repository in (("alice", "project"), ("bob", "other-project")):
            fork = self.new_repository(owner)
            oid = self.commit(fork, owner + "\n")
            self.git(fork, "branch", "topic")
            self.urls["https://github.com/" + owner + "/" + repository + ".git"] = fork.as_uri()
            ref = owner + ":topic" if repository == "project" else owner + ":" + repository + ":topic"
            expected[ref] = oid
            self.assert_resolves(destination, ref, oid)
        self.assertEqual(len(set(expected.values())), 2)
        for ref, oid in expected.items():
            self.assert_resolves(destination, ref, oid, offline=True)

    def test_fork_comparison_does_not_fetch_or_prune_unrelated_tags(self):
        destination = self.clone()
        self.git(destination, "tag", "local-only")
        self.git(destination, "config", "fetch.prune", "true")
        self.git(destination, "config", "fetch.pruneTags", "true")
        fork = self.new_repository("alice")
        self.commit(fork, "older tagged commit\n")
        self.git(fork, "tag", "fork-only")
        tip = self.commit(fork, "newer branch commit\n")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()

        self.assert_resolves(destination, "alice:main", tip)

        self.assertEqual(self.git(destination, "tag").stdout, "local-only\n")
        self.assertEqual(self.oid(destination, "refs/tags/local-only"), self.initial)

    def test_named_comparisons_refresh_and_keep_latest_snapshot_offline(self):
        for qualified in (False, True):
            with self.subTest(qualified=qualified):
                self.git(self.source, "switch", "--quiet", "main")
                repository = self.source
                ref = "topic"
                if qualified:
                    repository = self.new_repository("alice")
                    self.git(repository, "fetch", "--quiet", self.source.as_uri(), "main")
                    self.git(repository, "reset", "--hard", "FETCH_HEAD")
                    self.urls["https://github.com/alice/project.git"] = repository.as_uri()
                    ref = "alice:topic"
                self.git(repository, "branch", "topic")
                destination = self.clone()
                self.git(repository, "switch", "--quiet", "topic")

                for contents in ("first remote version\n", "second remote version\n"):
                    tip = self.commit(repository, contents)
                    expected = self.git(repository, "diff", self.initial + "..." + tip, "--").stdout
                    for offline in (False, True):
                        result = self.fish(
                            '__ghe_compare "$argv[1]" "$argv[2]" "$argv[3]"',
                            URL, destination, "main..." + ref, offline=offline,
                        )
                        self.assert_success(result)
                        self.assertEqual(result.stdout, expected)
                        self.assertTrue(self.transport)
                        if offline:
                            self.assertIn("cached", result.stderr)
                        else:
                            self.assertTrue(any(call["command"] == "fetch" for call in self.transport))
                        self.assertEqual(self.oid(destination), self.initial)
                        self.assertEqual((destination / "file.txt").read_text(), "initial\n")
                        self.assertEqual(self.git(destination, "status", "--porcelain").stdout, "")
                self.git(repository, "switch", "--quiet", "main")

    def test_named_comparison_rejects_tracking_written_through_a_custom_symref(self):
        destination = self.clone()
        foreign = self.new_repository("foreign")
        foreign_tip = self.commit(foreign, "foreign branch\n")
        alias = "refs/cache/foreign-main"
        tracking = "refs/remotes/origin/main"
        self.git(destination, "remote", "add", "other", foreign.as_uri())
        self.git(destination, "config", "--replace-all", "remote.other.fetch", "+refs/heads/main:" + alias)
        self.git(destination, "symbolic-ref", alias, tracking)
        self.git(destination, "fetch", "--quiet", "other")
        self.assertEqual(self.oid(destination, tracking), foreign_tip)

        result = self.compare_ref(destination, "main", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

        self.assert_resolves(destination, "main", self.initial)
        self.assertEqual(self.oid(destination, tracking), self.initial)
        self.assert_resolves(destination, "main", self.initial, offline=True)

    def test_named_comparison_follows_a_synchronized_tracking_ref_offline(self):
        destination = self.clone()
        self.assert_resolves(destination, "heads/main", self.initial)
        newer = self.commit(self.source, "fetched outside ghe\n")
        rewrite = "url." + self.source.as_uri() + ".insteadOf=" + URL
        self.git(destination, "-c", rewrite, "fetch", "--quiet", "origin")
        self.assert_resolves(destination, "main", newer, offline=True)
        self.assert_resolves(destination, "heads/main", newer, offline=True)

        self.assert_resolves(destination, "main", newer)
        self.git(self.source, "reset", "--hard", self.initial)
        self.git(destination, "-c", rewrite, "fetch", "--quiet", "origin")
        self.assert_resolves(destination, "main", self.initial, offline=True)
        self.assert_resolves(destination, "heads/main", self.initial, offline=True)

        self.git(destination, "update-ref", "-d", "refs/remotes/origin/main")
        self.assert_resolves(destination, "main", newer, offline=True)
        self.assert_resolves(destination, "heads/main", newer, offline=True)

    def test_bare_comparison_does_not_follow_a_branch_after_selecting_a_same_oid_tag(self):
        self.git(self.source, "branch", "release")
        self.git(self.source, "tag", "release")
        destination = self.clone()
        self.assert_resolves(destination, "release", self.initial)
        self.git(self.source, "branch", "--delete", "release")
        self.assert_resolves(destination, "release", self.initial)

        self.git(self.source, "switch", "--quiet", "--create", "release")
        newer = self.commit(self.source, "new release branch\n")
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                 "fetch", "--quiet", "origin")
        self.assert_resolves(destination, "release", self.initial, offline=True)
        self.assert_resolves(destination, "heads/release", newer, offline=True)

    def test_offline_comparison_rejects_local_branch_as_a_tracking_snapshot(self):
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/main:refs/heads/main")
        local = self.commit(destination, "unpublished local commit\n")

        result = self.compare_ref(destination, "main", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.oid(destination), local)
        self.assert_resolves(destination, "main", self.initial)
        self.assert_resolves(destination, "main", self.initial, offline=True)

    def test_named_comparison_works_when_a_snapshot_ref_is_locked(self):
        destination = self.clone()
        self.assert_resolves(destination, "main", self.initial)
        newer = self.commit(self.source, "updated main\n")
        identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
        cache = f"refs/gh/compare/{identity}/by-ref"
        keys = [self.git(destination, "hash-object", "--stdin", input=ref + "\n").stdout.strip()
                for ref in ("main", "refs/heads/main")]
        lock = destination / ".git" / f"{cache}/{keys[1]}.lock"
        lock.write_text("held by another process\n")

        self.assert_resolves(destination, "main", newer)

        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        for key in keys:
            self.assertEqual(self.oid(destination, f"{cache}/{key}"), self.initial)

    def test_delayed_comparison_keeps_a_newer_tracked_snapshot(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        first = self.commit(self.source, "first topic tip\n")
        second = self.commit(self.source, "second topic tip\n")
        self.git(self.source, "switch", "--quiet", "main")
        self.git(self.source, "branch", "--force", "topic", first)
        destination = self.clone()

        result = self.fish("""set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
set -g newer "$argv[4]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" update-ref refs/heads/topic "$newer"; or return
        __ghe_compare_ref "$repository" "$checkout" topic >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" topic""", URL, destination, self.source, second)

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), first)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/topic"), second)
        for ref in ("topic", "heads/topic"):
            self.assert_resolves(destination, ref, second, offline=True)

    def test_delayed_comparison_does_not_replace_a_newer_tag_snapshot(self):
        self.git(self.source, "tag", "release")
        destination = self.clone()
        self.assert_resolves(destination, "release", self.initial)
        newer = self.commit(self.source, "moved release tag\n")

        result = self.fish("""set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
set -g newer "$argv[4]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" update-ref refs/tags/release "$newer"; or return
        __ghe_compare_ref "$repository" "$checkout" tags/release >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" release""", URL, destination, self.source, newer)

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), self.initial)
        self.assert_resolves(destination, "tags/release", newer, offline=True)

    def test_delayed_comparison_cannot_restore_a_branch_after_selecting_a_same_oid_tag(self):
        self.git(self.source, "branch", "release")
        self.git(self.source, "tag", "release")
        destination = self.clone()
        self.assert_resolves(destination, "release", self.initial)
        newer = self.commit(self.source, "new release branch\n")

        result = self.fish("""set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" branch --delete release >/dev/null; or return
        __ghe_compare_ref "$repository" "$checkout" release >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" release""", URL, destination, self.source)

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), self.initial)
        self.git(self.source, "branch", "release", newer)
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                 "fetch", "--quiet", "origin", "refs/heads/release")
        self.assert_resolves(destination, "release", self.initial, offline=True)
        self.assert_resolves(destination, "heads/release", newer, offline=True)

    def test_moved_tag_and_branch_to_tag_comparison_keep_latest_snapshot(self):
        self.git(self.source, "tag", "release")
        self.git(self.source, "branch", "release")
        destination = self.clone()
        newer = self.commit(self.source, "retagged version\n")
        self.git(self.source, "tag", "--force", "release", newer)

        self.assert_resolves(destination, "tags/release", newer)
        self.assert_resolves(destination, "tags/release", newer, offline=True)

        self.assert_resolves(destination, "release", self.initial)
        self.git(self.source, "branch", "--delete", "release")
        self.assert_resolves(destination, "release", newer)
        self.assert_resolves(destination, "release", newer, offline=True)

        self.assertEqual(self.oid(destination, "refs/tags/release"), self.initial)
        self.assertEqual(self.oid(destination), self.initial)

    def test_deleted_comparison_ref_does_not_fall_back_to_stale_cache(self):
        for namespace, ref in (("heads", "topic"), ("tags", "tags/topic")):
            with self.subTest(namespace=namespace):
                source_ref = "refs/" + namespace + "/topic"
                self.git(self.source, "update-ref", source_ref, self.initial)
                destination = self.clone()
                self.assert_resolves(destination, ref, self.initial)
                self.git(self.source, "update-ref", "-d", source_ref)

                result = self.compare_ref(destination, ref)

                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout, "")
                self.assertIn("no branch, tag, or commit matches", result.stderr)
                self.assertTrue(any(call["command"] == "ls-remote" for call in self.transport))
                self.assertEqual(self.oid(destination), self.initial)

    def test_hex_named_comparison_branch_is_refreshed(self):
        self.git(self.source, "branch", "2026")
        destination = self.clone()
        newer = self.commit(self.source, "new hexadecimal branch version\n")
        self.git(self.source, "branch", "--force", "2026", newer)

        self.assert_resolves(destination, "2026", newer)
        self.assertTrue(any(call["command"] == "fetch" for call in self.transport))
        self.assert_resolves(destination, "2026", newer, offline=True)

    def test_named_comparison_has_no_array_index_errors_with_bsd_seq(self):
        destination = self.clone()
        newer = self.commit(self.source, "updated main\n")

        result = self.fish(
            """function seq
    if test "$argv" = 0
        printf '%s\\n' 1 0
    else
        command seq $argv
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" main""",
            URL, destination,
        )

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), newer)
        self.assertEqual(result.stderr, "")

    def test_cached_comparison_commit_ids_do_not_attempt_transport(self):
        destination = self.clone()
        for ref in (self.initial, self.initial[:10]):
            for offline in (False, True):
                with self.subTest(ref=ref, offline=offline):
                    result = self.compare_ref(destination, ref, offline=offline)
                    self.assert_success(result)
                    self.assertEqual(result.stdout.strip(), self.initial)
                    self.assertEqual(self.transport, [])

    def test_cached_comparison_tips_fetch_a_missing_shallow_merge_base(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        head = self.commit(self.source, "topic change\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")
        base = self.commit(self.source, "main change\n", "main.txt")
        for length in (40, 10):
            with self.subTest(length=length):
                destination = self.clone(depth=1)
                self.git(destination, "fetch", "--quiet", "--depth=1", self.source.as_uri(), "refs/heads/topic")
                before = self.git(destination, "for-each-ref").stdout
                compare = '__ghe_compare "$argv[1]" "$argv[2]" "$argv[3]"'

                two_dot = self.fish(compare, URL, destination, f"{base[:length]}..{head[:length]}", offline=True)
                self.assert_success(two_dot)
                self.assertEqual(self.transport, [])

                range_spec = f"{base[:length]}...{head[:length]}"
                offline = self.fish(compare, URL, destination, range_spec, offline=True)
                self.assertEqual(offline.returncode, 1)
                self.assertIn("comparison has no local merge base", offline.stderr)
                self.assertEqual([call["command"] for call in self.transport], ["fetch"])

                online = self.fish(compare, URL, destination, range_spec)
                self.assert_success(online)
                self.assertIn("+topic change", online.stdout)
                self.assertNotIn("main.txt", online.stdout)
                self.assertEqual([call["command"] for call in self.transport], ["fetch"])
                self.assertEqual(self.git(destination, "for-each-ref").stdout, before)

                cached = self.fish(compare, URL, destination, range_spec, offline=True)
                self.assert_success(cached)
                self.assertEqual(cached.stdout, online.stdout)
                self.assertEqual(self.transport, [])

    def test_cached_comparison_ancestors_fetch_a_missing_shallow_merge_base(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        self.commit(self.source, "topic parent\n", "topic.txt")
        head = self.commit(self.source, "topic change\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")
        parent = self.commit(self.source, "main parent\n", "main.txt")
        tip = self.commit(self.source, "main tip\n", "main.txt")
        destination = self.clone(depth=2)
        self.git(destination, "fetch", "--quiet", "--depth=2", self.source.as_uri(), "refs/heads/topic")
        self.assertEqual(self.oid(destination, tip + "~1"), parent)
        self.assertEqual(self.git(destination, "merge-base", parent, head, check=False).returncode, 1)

        compare = '__ghe_compare "$argv[1]" "$argv[2]" "$argv[3]"'
        range_spec = f"{tip[:10]}~1...{head}"
        result = self.fish(compare, URL, destination, range_spec)
        self.assert_success(result)
        self.assertIn("+topic change", result.stdout)
        self.assertEqual([call["command"] for call in self.transport], ["fetch"])

    def test_shallow_three_dot_comparison_checks_for_a_closer_merge_base(self):
        for generation in range(3):
            anchor = self.commit(self.source, f"ancestor {generation}\n", "ancestor.txt")
        for side in ("left-side", "right-side"):
            self.git(self.source, "switch", "--quiet", "--create", side, "main")
            self.commit(self.source, side + "\n", side + ".txt")
        self.git(self.source, "switch", "--quiet", "main")
        common = self.commit(self.source, "already shared\n", "shared.txt")
        self.git(self.source, "branch", "topic")
        tips = []
        for branch, side in (("topic", "right-side"), ("main", "left-side")):
            self.git(self.source, "switch", "--quiet", branch)
            self.commit(self.source, branch + " parent\n", branch + ".txt")
            self.commit(self.source, branch + " change\n", branch + ".txt")
            self.git(self.source, "merge", "--quiet", "--no-edit", "--no-ff", side)
            tips.append(self.oid(self.source))
        head, base = tips
        range_spec = f"{base}...{head}"
        compare = '__ghe_compare "$argv[1]" "$argv[2]" "$argv[3]"'
        expected = self.git(self.source, "diff", range_spec, "--").stdout
        self.assertNotIn("shared.txt", expected)

        for depth, local_base in ((3, anchor), (5, common)):
            with self.subTest(depth=depth):
                destination = self.clone(depth=depth)
                self.git(destination, "fetch", "--quiet", f"--depth={depth}", self.source.as_uri(), "refs/heads/topic")
                self.assertEqual(self.git(destination, "merge-base", base, head).stdout.strip(), local_base)
                self.assertEqual(self.git(destination, "rev-parse", "--is-shallow-repository").stdout.strip(), "true")
                offline = self.fish(compare, URL, destination, range_spec, offline=True)
                if depth == 5:
                    self.assert_success(offline)
                    self.assertEqual(offline.stdout, expected)
                    self.assertEqual(self.transport, [])
                    continue

                self.assertNotEqual(offline.returncode, 0)
                self.assertIn("shallow history may hide a closer comparison merge base", offline.stderr)
                self.assertEqual(offline.stdout, "")
                self.assertEqual([call["command"] for call in self.transport], ["fetch"])

                self.git(destination, "config", "--add", "remote.origin.fetch",
                         "+refs/heads/topic:refs/remotes/origin/topic")
                self.git(destination, "update-ref", "refs/remotes/origin/topic", head)
                mixed = self.fish(compare, URL, destination, f"{base}...topic", offline=True)
                self.assertNotEqual(mixed.returncode, 0)
                self.assertIn("shallow history may hide a closer comparison merge base", mixed.stderr)
                self.assertEqual(mixed.stdout, "")

                online = self.fish(compare, URL, destination, range_spec)
                self.assert_success(online)
                self.assertEqual(online.stdout, expected)
                self.assertEqual([call["command"] for call in self.transport], ["fetch"])

    def test_cached_commit_ancestry_in_shallow_clone_fetches_missing_history(self):
        parent = self.commit(self.source, "parent\n")
        tip = self.commit(self.source, "tip\n")
        for ref in (tip + "~1", tip[:10] + "~1"):
            with self.subTest(ref=ref):
                destination = self.clone(depth=1)
                self.assertEqual(self.git(destination, "rev-parse", "--is-shallow-repository").stdout.strip(), "true")

                result = self.compare_ref(destination, ref)

                self.assert_success(result)
                self.assertEqual(result.stdout.strip(), parent)
                self.assertTrue(any(call["command"] == "fetch" for call in self.transport))
                self.assertEqual(self.oid(destination), tip)
                self.assertEqual((destination / "file.txt").read_text(), "tip\n")

    def test_head_file_open_follows_pulls_and_comparisons_in_observation_order(self):
        for mapping in ("+refs/heads/*:refs/remotes/origin/*", "+refs/heads/*:refs/cache/origin/*",
                        "+refs/heads/*:refs/custom/origin/*"):
            with self.subTest(mapping=mapping):
                destination = self.clone()
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", mapping)
                self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                         "fetch", "--quiet", "origin")
                self.assert_resolves(destination, "HEAD", self.oid(self.source))
                pulled = self.commit(self.source, "pulled default version\n")
                self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                         "pull", "--quiet", "--ff-only", "origin", "main")
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), pulled)
                compared = self.commit(self.source, "comparison default version\n")
                self.assert_resolves(destination, "HEAD", compared)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), compared)
                self.assertEqual(self.transport, [])

    def test_head_comparison_refreshes_tracking_on_force_rewind_and_divergence(self):
        destination = self.clone()
        newer = self.commit(self.source, "new remote version\n")
        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        self.git(self.source, "reset", "--hard", self.initial)
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                 "fetch", "--quiet", "origin")
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), self.initial)
        divergent = self.commit(self.source, "divergent remote version\n")
        self.assert_resolves(destination, "HEAD", divergent)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), divergent)
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), divergent)

    def test_head_comparison_updates_tracking_after_force_push_without_local_fetch(self):
        destination = self.clone()
        tracking = self.matching_remote(destination, tracking="refs/cache/aaa/main")
        pushed = self.commit(self.source, "default before force push\n")
        self.assert_resolves(destination, "HEAD", pushed)
        self.git(self.source, "reset", "--hard", self.initial)
        rewritten = self.commit(self.source, "force-pushed default\n")

        self.assert_resolves(destination, "HEAD", rewritten)

        self.assertEqual([call["command"] for call in self.transport], ["ls-remote", "fetch"])
        for remote, target in (("aaa", tracking), ("origin", "refs/remotes/origin/main")):
            self.assertEqual(self.oid(destination, target), rewritten)
            self.assertEqual(self.git(destination, "symbolic-ref", "refs/remotes/" + remote + "/HEAD").stdout.strip(), target)
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), rewritten)
        self.assertEqual(self.transport, [])

    def test_case_distinct_branches_do_not_shadow_existing_tracking_refs(self):
        self.git(self.source, "switch", "--quiet", "--create", "Topic")
        earlier = self.commit(self.source, "uppercase branch\n", "upper.txt")
        self.git(self.source, "switch", "--quiet", "main")
        destinations = [self.clone(), self.clone()]
        self.git(self.source, "pack-refs", "--all", "--prune")
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        newer = self.commit(self.source, "lowercase branch\n")
        for packed, destination in zip((True, False), destinations):
            with self.subTest(packed=packed):
                tracking = "refs/remotes/origin/Topic"
                if not packed:
                    self.git(destination, "update-ref", "-d", tracking)
                    self.git(destination, "update-ref", tracking, earlier)
                refs = destination / ".git" / "refs"
                upper_refs = refs.with_name("REFS")
                folds_case = upper_refs.exists() and refs.samefile(upper_refs)
                offline = self.compare_ref(destination, "topic", offline=True)
                self.assertNotEqual(offline.returncode, 0)
                self.assert_resolves(destination, "topic", newer)
                self.assertEqual(self.oid(destination, tracking), earlier)

                result = self.checkout(destination, "blob/topic/file.txt")
                if folds_case:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("tracking ref conflicts with a differently spelled ref", result.stderr)
                    self.assertEqual(self.oid(destination), self.initial)
                else:
                    self.assert_success(result)
                    self.assertEqual(self.oid(destination), newer)
                self.assertEqual(self.oid(destination, tracking), earlier)

                if folds_case and not packed:
                    self.git(destination, "branch", "Topic", self.initial)
                    result = self.checkout(destination, "blob/topic/file.txt")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("local branch conflicts with a differently spelled ref", result.stderr)
                    self.assertEqual(self.oid(destination), self.initial)
                    self.git(destination, "branch", "--delete", "Topic")

                    self.git(destination, "switch", "--quiet", "--create", "topic", earlier)
                    self.git(destination, "config", "branch.topic.remote", "origin")
                    self.git(destination, "config", "branch.topic.merge", "refs/heads/topic")
                    result = self.fish('__gho_url "$argv[1]"', destination / "upper.txt", offline=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("cached remote branch conflicts with a differently spelled ref", result.stderr)
                    self.assertEqual(self.transport, [])

    def test_compare_does_not_read_or_overwrite_a_unicode_loose_ref_alias(self):
        self.git(self.source, "switch", "--quiet", "--create", "münchen")
        older = self.commit(self.source, "lowercase branch\n")
        self.git(self.source, "switch", "--quiet", "main")
        destination = self.clone()
        tracking = "refs/remotes/origin/münchen"
        self.git(destination, "update-ref", "-d", tracking)
        self.git(destination, "update-ref", tracking, older)
        self.git(self.source, "pack-refs", "--all", "--prune")
        self.git(self.source, "switch", "--quiet", "--create", "MÜNCHEN")
        newer = self.commit(self.source, "uppercase branch\n")

        self.assertNotEqual(self.compare_ref(destination, "MÜNCHEN", offline=True).returncode, 0)
        self.assert_resolves(destination, "MÜNCHEN", newer)
        self.assertEqual(self.oid(destination, tracking), older)

        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/MÜNCHEN:refs/remotes/origin/MÜNCHEN")
        self.git(destination, "branch", "--move", "MÜNCHEN")
        self.git(destination, "config", "branch.MÜNCHEN.merge", "refs/heads/MÜNCHEN")
        result = self.fish('__ghe_pull "$argv[1]" "$argv[2]" MÜNCHEN file.txt', destination, URL)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.oid(destination, tracking), older)

        self.git(destination, "update-ref", "refs/tags/café", older)
        self.assert_resolves(destination, "tags/café", older, offline=True)
        self.assertNotEqual(self.compare_ref(destination, "tags/cafe\u0301", offline=True).returncode, 0)

    def test_missing_full_tag_does_not_resolve_through_a_nested_tag(self):
        destination = self.clone()
        self.git(destination, "tag", "--annotate", "--message", "nested tag", "refs/tags/release")
        self.assert_resolves(destination, "tags/refs/tags/release", self.initial, offline=True)

        result = self.compare_ref(destination, "tags/release", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_gho_does_not_use_a_tag_in_place_of_a_missing_tracking_ref(self):
        destination = self.clone()
        tracking = "refs/remotes/origin/main"
        self.git(destination, "update-ref", "-d", tracking)
        self.git(destination, "tag", tracking, self.initial)

        result = self.fish('__gho_url "$argv[1]"', destination / "file.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("branch has not been pushed or fetched", result.stderr)
        self.assertEqual(self.transport, [])

    def test_offline_tag_comparison_does_not_reuse_a_differently_cased_tag(self):
        self.git(self.source, "tag", "Release")
        destination = self.clone()
        self.git(destination, "update-ref", "-d", "refs/tags/Release")
        self.git(destination, "update-ref", "refs/tags/Release", self.initial)
        self.assert_resolves(destination, "tags/Release", self.initial, offline=True)
        result = self.compare_ref(destination, "tags/release", offline=True)
        self.assertNotEqual(result.returncode, 0)

        self.git(self.source, "pack-refs", "--all", "--prune")
        newer = self.commit(self.source, "lowercase release\n")
        self.git(self.source, "tag", "release")
        self.assert_resolves(destination, "tags/release", newer)
        self.assertEqual(self.oid(destination, "refs/tags/Release"), self.initial)
        self.assert_resolves(destination, "tags/release", newer, offline=True)
        self.assert_resolves(destination, "tags/Release", self.initial, offline=True)

    def test_topic_comparison_updates_tracking_after_force_push_without_local_fetch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        self.commit(self.source, "topic before force push\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")
        destination = self.clone()
        self.git(self.source, "switch", "--quiet", "topic")
        self.git(self.source, "reset", "--hard", self.initial)
        rewritten = self.commit(self.source, "force-pushed topic\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")

        self.assert_resolves(destination, "topic", rewritten)

        self.assertEqual([call["command"] for call in self.transport], ["ls-remote", "fetch"])
        self.assertEqual(self.oid(destination, "refs/remotes/origin/topic"), rewritten)

    def test_head_open_follows_updates_through_each_matching_remote(self):
        for remote in ("aaa", "origin"):
            with self.subTest(remote=remote):
                destination = self.clone()
                tracking = self.matching_remote(destination, tracking="refs/cache/aaa/main")
                self.assert_resolves(destination, "HEAD", self.oid(self.source))
                newer = self.commit(self.source, "pulled through " + remote + "\n")
                self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                         "pull", "--quiet", "--ff-only", remote, "main")
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), newer)
                self.assertEqual(self.transport, [])
                compared = self.commit(self.source, "compared after " + remote + "\n")
                self.assert_resolves(destination, "HEAD", compared)
                for target in (tracking, "refs/remotes/origin/main"):
                    self.assertEqual(self.oid(destination, target), compared)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), compared)
                self.assertEqual(self.transport, [])

        with self.subTest(remote="newly added zzz without a HEAD alias"):
            destination = self.clone()
            self.assert_resolves(destination, "HEAD", self.oid(self.source))
            self.git(destination, "remote", "add", "zzz", URL)
            newer = self.commit(self.source, "pulled through a new matching remote\n")
            self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                     "pull", "--quiet", "--ff-only", "zzz", "main")
            result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.oid(destination), newer)
            self.assert_success(self.checkout(destination, "blob/HEAD/file.txt"))
            self.assertEqual(self.oid(destination), newer)
            self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
            self.assertEqual(self.oid(destination), newer)
            self.assertEqual(self.transport, [])

    def test_head_open_follows_nonquery_remote_rewinds_and_divergence(self):
        self.commit(self.source, "initial synchronized tip\n")
        destination = self.clone()
        self.matching_remote(destination)
        self.assert_resolves(destination, "HEAD", self.oid(self.source))
        self.git(self.source, "reset", "--hard", self.initial)
        for expected in (self.initial, None):
            if expected is None:
                expected = self.commit(self.source, "divergent nonquery tip\n")
            self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                     "fetch", "--quiet", "origin")
            self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
            self.assertEqual(self.oid(destination), expected)
            self.assertEqual(self.transport, [])

    def test_matching_remote_head_conflicts_require_refresh(self):
        for conflict in ("multiple_updates", "missing_marker", "legacy"):
            with self.subTest(conflict=conflict):
                destination = self.clone()
                self.matching_remote(destination)
                if conflict != "legacy":
                    self.assert_resolves(destination, "HEAD", self.oid(self.source))
                self.commit(self.source, conflict + " first observation\n")
                self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                         "fetch", "--quiet", "aaa")
                if conflict == "multiple_updates":
                    self.commit(self.source, "second independent observation\n")
                    self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                             "fetch", "--quiet", "origin")
                elif conflict == "missing_marker":
                    markers = self.git(destination, "for-each-ref", "--format=%(refname)", "refs/gh/compare/").stdout.splitlines()
                    for marker in markers:
                        if "/tracking-synced/" in marker:
                            self.git(destination, "update-ref", "-d", marker)
                before = self.oid(destination)
                result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot refresh default HEAD", result.stderr)
                self.assertEqual(self.oid(destination), before)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt"))
                self.assertEqual(self.oid(destination), self.oid(self.source))
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.transport, [])

    def test_matching_remotes_can_share_a_tracking_destination(self):
        destination = self.clone()
        self.matching_remote(destination, tracking="refs/remotes/origin/main")
        newer = self.commit(self.source, "shared tracking target\n")
        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.transport, [])

    def test_failed_matching_remote_sync_invalidates_all_default_aliases(self):
        destination = self.clone()
        tracking = self.matching_remote(destination)
        self.assert_resolves(destination, "HEAD", self.initial)
        newer = self.commit(self.source, "partially synchronized default\n")
        lock = destination / ".git/refs/remotes/origin/main.lock"
        lock.write_text("held by another process\n")
        self.assert_resolves(destination, "HEAD", newer)
        for ref in (tracking, "refs/remotes/origin/main"):
            self.assertEqual(self.oid(destination, ref), self.initial)
        for remote in ("aaa", "origin"):
            self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "refs/remotes/" + remote + "/HEAD", check=False).returncode, 0)
        before = self.oid(destination)
        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.oid(destination), before)

    def test_matching_remote_alias_cannot_replace_another_tracking_target(self):
        destination = self.clone()
        self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        self.git(destination, "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/cache/origin/main")
        self.matching_remote(destination, tracking="refs/remotes/origin/HEAD")
        newer = self.commit(self.source, "cross-remote alias collision\n")
        self.assert_resolves(destination, "HEAD", newer)
        for target in ("refs/remotes/origin/HEAD", "refs/cache/origin/main"):
            self.assertEqual(self.oid(destination, target), newer)
            self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", target, check=False).returncode, 0)
        before = self.oid(destination)
        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.oid(destination), before)

    def test_delayed_default_comparison_cannot_restore_the_old_default_branch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        newer = self.commit(self.source, "new default\n")
        self.git(self.source, "switch", "--quiet", "main")
        for tip in (self.initial, newer):
            with self.subTest(same_commit=tip == self.initial):
                self.git(self.source, "branch", "--force", "topic", tip)
                destination = self.clone()
                self.assert_resolves(destination, "HEAD", self.initial)

                result = self.fish("""set -g repository "$argv[1]"
set -g checkout "$argv[2]"
set -g source "$argv[3]"
function git
    command git $argv; or return
    if not set -q interleaved; and contains -- fetch $argv; and contains -- --stdin $argv
        set -g interleaved true
        command git -C "$source" symbolic-ref HEAD refs/heads/topic; or return
        __ghe_compare_ref "$repository" "$checkout" HEAD >/dev/null; or return
    end
end
__ghe_compare_ref "$repository" "$checkout" HEAD""", URL, destination, self.source)

                self.assert_success(result)
                self.assertEqual(result.stdout.strip(), self.initial)
                self.assertEqual(self.git(destination, "symbolic-ref", "refs/remotes/origin/HEAD").stdout.strip(),
                                 "refs/remotes/origin/topic")
                self.git(self.source, "symbolic-ref", "HEAD", "refs/heads/main")
                if tip == self.initial:
                    self.git(self.source, "branch", "--force", "topic", newer)
                    self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                             "fetch", "--quiet", "origin", "topic")
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), newer)
                self.assertEqual(self.transport, [])

    def test_head_comparison_updates_default_alias_without_overwriting_old_branch(self):
        destination = self.clone()
        self.assert_resolves(destination, "HEAD", self.initial)
        self.git(self.source, "switch", "--quiet", "--create", "new-default")
        newer = self.commit(self.source, "new default branch\n")
        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/new-default"), newer)
        self.assertEqual(self.git(destination, "symbolic-ref", "refs/remotes/origin/HEAD").stdout.strip(),
                         "refs/remotes/origin/new-default")
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), newer)

    def test_head_comparison_succeeds_when_a_dangling_symref_blocks_its_alias(self):
        destination = self.clone()
        alias = "refs/remotes/origin/HEAD"
        self.git(destination, "symbolic-ref", "--delete", alias)
        blocker = alias + "/marker"
        target = "refs/heads/missing"
        self.git(destination, "symbolic-ref", blocker, target)
        newer = self.commit(self.source, "blocked default alias\n")

        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        self.assertEqual(self.git(destination, "symbolic-ref", blocker).stdout.strip(), target)

    def test_head_comparison_preserves_direct_and_overlapping_tracking_destinations(self):
        for target in ("refs/remotes/origin/HEAD", "refs/remotes/origin/HEAD/main", "refs/remotes/origin"):
            with self.subTest(target=target):
                destination = self.clone()
                self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
                self.git(destination, "update-ref", "-d", "refs/remotes/origin/main")
                self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                         "+refs/heads/main:" + target)
                compared = self.commit(self.source, "comparison for " + target + "\n")
                before = self.oid(destination)

                self.assert_resolves(destination, "HEAD", compared)
                self.assertEqual(self.oid(destination, target), compared)
                self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", target, check=False).returncode, 0)
                self.assertEqual(self.oid(destination), before)
                fetched = self.commit(self.source, "ordinary fetch for " + target + "\n")
                self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                         "fetch", "--quiet", "origin")
                self.assertEqual(self.oid(destination, target), fetched)
                self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", target, check=False).returncode, 0)
                self.assertEqual(self.oid(destination), before)

    def test_direct_default_tracking_destination_follows_later_fetch_offline(self):
        destination = self.clone()
        self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/main:refs/remotes/origin/HEAD")
        compared = self.commit(self.source, "direct default comparison\n")
        self.assert_resolves(destination, "HEAD", compared)
        fetched = self.commit(self.source, "direct default ordinary fetch\n")
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                 "fetch", "--quiet", "origin")

        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.oid(destination), fetched)
        self.assertEqual(self.transport, [])
        self.assertEqual(self.oid(destination, "refs/remotes/origin/HEAD"), fetched)
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", check=False).returncode, 0)

    def test_failed_direct_default_update_does_not_reuse_the_previous_head_snapshot(self):
        destination = self.clone()
        ref = "refs/remotes/origin/HEAD"
        self.git(destination, "symbolic-ref", "--delete", ref)
        self.git(destination, "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:" + ref)
        self.assert_resolves(destination, "HEAD", self.initial)
        newer = self.commit(self.source, "new default during tracking lock\n")
        lock = destination / ".git/refs/remotes/origin/HEAD.lock"
        lock.write_text("held by another process\n")
        self.assert_resolves(destination, "main", newer)

        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot refresh default HEAD", result.stderr)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertEqual(self.oid(destination, ref), self.initial)
        lock.unlink()
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt"))
        self.assertEqual(self.oid(destination), newer)
        self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
        self.assertEqual(self.transport, [])

    def test_direct_default_alias_requires_an_active_round_trip_fetch_mapping(self):
        for restriction in ("unmapped", "excluded", "secondary"):
            with self.subTest(restriction=restriction):
                destination = self.clone()
                self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
                self.git(destination, "update-ref", "refs/remotes/origin/HEAD", self.initial)
                target = "refs/remotes/origin/HEAD" if restriction == "excluded" else "refs/custom/main"
                self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                         "+refs/heads/main:" + target)
                if restriction == "excluded":
                    self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/main")
                elif restriction == "secondary":
                    self.git(destination, "config", "--add", "remote.origin.fetch",
                             "+refs/heads/main:refs/remotes/origin/HEAD")

                result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot refresh default HEAD", result.stderr)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertEqual(self.oid(destination, "refs/remotes/origin/HEAD"), self.initial)

    def test_direct_default_alias_requires_an_explicit_fetch_destination(self):
        destination = self.clone()
        self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
        self.git(destination, "update-ref", "refs/remotes/origin/HEAD", self.initial)

        result = self.fish('__gh_default_ref origin "$argv[1]" (__gh_refspecs origin "$argv[1]")',
                           destination, offline=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.transport, [])

    def test_missing_default_alias_is_not_inferred_from_a_wildcard_mapping(self):
        destination = self.clone()
        self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")

        result = self.fish(
            'set -l specs (__gh_refspecs origin "$argv[1]"); __gh_default_ref origin "$argv[1]" $specs',
            destination, offline=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.transport, [])

    def test_head_open_refreshes_unsafe_mapping_without_modifying_its_target(self):
        for mapping in ("+refs/heads/main:refs/heads/main", "+refs/heads/main:refs/tags/local-copy"):
            with self.subTest(mapping=mapping):
                destination = self.clone()
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", mapping)
                before = self.oid(destination)
                newer = self.commit(self.source, "unsafe mapping comparison " + mapping + "\n")
                self.assert_resolves(destination, "HEAD", newer)
                self.assertEqual(self.oid(destination), before)
                result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot refresh default HEAD", result.stderr)
                self.assertEqual(self.oid(destination), before)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt"))
                self.assertEqual(self.oid(destination), newer)

    def test_head_open_does_not_trust_a_negatively_excluded_default(self):
        destination = self.clone()
        self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/main")
        newer = self.commit(self.source, "excluded default comparison\n")
        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot refresh default HEAD", result.stderr)
        self.assertEqual(self.oid(destination), self.initial)

    def test_head_comparison_handles_tracking_refs_overlapping_its_alias(self):
        for spec, tracking in (
            ("+refs/heads/main:refs/remotes/origin/HEAD", "refs/remotes/origin/HEAD"),
            ("+refs/heads/*:refs/remotes/origin/HEAD/*", "refs/remotes/origin/HEAD/main"),
            ("+refs/heads/main:refs/remotes/origin", "refs/remotes/origin"),
            ("+refs/heads/main:refs/remotes/origin/head", "refs/remotes/origin/head"),
            ("+refs/heads/*:refs/remotes/origin/head/*", "refs/remotes/origin/head/main"),
            ("+refs/heads/main:refs/remotes/Origin", "refs/remotes/Origin"),
        ):
            with self.subTest(spec=spec):
                destination = self.clone()
                self.git(destination, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD")
                self.git(destination, "update-ref", "-d", "refs/remotes/origin/main")
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", spec)
                newer = self.commit(self.source, spec + "\n")

                self.assert_resolves(destination, "HEAD", newer)
                self.assertEqual(self.oid(destination, tracking), newer)
                self.assertNotEqual(
                    self.git(destination, "symbolic-ref", "--quiet", "--no-recurse",
                             "refs/remotes/origin/HEAD", check=False).returncode,
                    0,
                )
                self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin', destination))

    def test_changed_default_with_no_safe_mapping_invalidates_the_old_alias(self):
        for restriction in ("unmapped", "excluded", "local_branch", "symbolic"):
            with self.subTest(restriction=restriction):
                self.git(self.source, "switch", "--quiet", "main")
                destination = self.clone()
                self.assert_resolves(destination, "HEAD", self.oid(self.source))
                self.git(self.source, "switch", "--quiet", "--create", "new-" + restriction)
                newer = self.commit(self.source, "new unmapped default\n")
                if restriction == "unmapped":
                    self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                             "+refs/heads/main:refs/remotes/origin/main")
                elif restriction == "excluded":
                    self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/new-" + restriction)
                elif restriction == "local_branch":
                    self.git(destination, "config", "--add", "remote.origin.fetch",
                             "+refs/heads/new-local_branch:refs/heads/local-copy")
                    self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                             "+refs/heads/main:refs/remotes/origin/main", "refs/heads/\\*")
                else:
                    self.git(destination, "symbolic-ref", "refs/remotes/origin/new-symbolic", "refs/heads/main")
                self.assert_resolves(destination, "HEAD", newer)
                self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", check=False).returncode, 0)
                result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot refresh default HEAD", result.stderr)
                self.assertEqual(self.oid(destination), self.oid(destination, "refs/heads/main"))

    def test_comparison_survives_a_stale_tracking_ref_hierarchy(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(self.source, "branch", "--delete", "topic")
        self.git(self.source, "switch", "--quiet", "--create", "topic/fix")
        newer = self.commit(self.source, "new topic hierarchy\n")
        self.assert_resolves(destination, "heads/topic/fix", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/topic"), self.initial)
        self.assertEqual(self.oid(destination), self.initial)

    def test_failed_default_tracking_update_requires_refresh_instead_of_old_head_cache(self):
        destination = self.clone()
        self.assert_resolves(destination, "HEAD", self.initial)
        newer = self.commit(self.source, "locked default tracking\n")
        lock = destination / ".git/refs/remotes/origin/main.lock"
        lock.write_text("held by another process\n")
        self.assert_resolves(destination, "main", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", check=False).returncode, 0)
        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot refresh default HEAD", result.stderr)
        self.assertEqual(self.oid(destination), self.initial)

    def test_legacy_head_snapshot_conflict_requires_one_online_synchronization(self):
        for snapshot_position in ("newer", "older"):
            with self.subTest(snapshot_position=snapshot_position):
                destination = self.clone()
                before = self.oid(destination)
                newer = self.commit(self.source, "legacy " + snapshot_position + " snapshot\n")
                if snapshot_position == "newer":
                    self.git(destination, "fetch", "--quiet", "--refmap=", self.source.as_uri(), "main")
                    snapshot = newer
                else:
                    self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL,
                             "pull", "--quiet", "--ff-only", "origin", "main")
                    snapshot = before
                    before = newer
                identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
                key = self.git(destination, "hash-object", "--stdin", input="HEAD\n").stdout.strip()
                self.git(destination, "update-ref", "refs/gh/compare/" + identity + "/by-ref/" + key, snapshot)
                result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot refresh default HEAD", result.stderr)
                self.assertEqual(self.oid(destination), before)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt"))
                self.assertEqual(self.oid(destination), newer)
                self.assert_success(self.checkout(destination, "blob/HEAD/file.txt", offline=True))
                self.assertEqual(self.oid(destination), newer)
                self.assertEqual(self.transport, [])

    def test_head_file_open_refreshes_a_cached_default_missing_the_path(self):
        destination = self.clone()
        newer = self.commit(self.source, "added upstream\n", "new.txt")

        result = self.checkout(destination, "blob/HEAD/new.txt", offline=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("path does not exist", result.stderr)
        self.assertEqual(self.oid(destination), self.initial)

        self.assert_success(self.checkout(destination, "blob/HEAD/new.txt"))
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        self.assertEqual((destination / "new.txt").read_text(), "added upstream\n")
        self.assert_success(self.checkout(destination, "blob/HEAD/new.txt", offline=True))
        self.assertEqual(self.transport, [])

    def test_unmapped_head_refresh_does_not_cache_a_new_default_under_the_old_branch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        topic = self.commit(self.source, "new default branch\n")
        self.git(self.source, "switch", "--quiet", "main")
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/topic:refs/remotes/origin/topic")
        self.assert_resolves(destination, "main", self.initial)

        result = self.fish("""set -g source "$argv[3]"
function git
    command git $argv; or return
    if contains -- ls-remote $argv; and contains -- HEAD $argv
        command git -C "$source" symbolic-ref HEAD refs/heads/topic; or return
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" HEAD""", URL, destination, self.source)

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), topic)
        self.assert_resolves(destination, "HEAD", topic, offline=True)
        for ref in ("main", "heads/main"):
            self.assert_resolves(destination, ref, self.initial, offline=True)

    def test_head_comparison_refreshes_default_branch_snapshot_offline(self):
        destination = self.clone()
        self.assert_resolves(destination, "main", self.initial)
        newer = self.commit(self.source, "default moved before a HEAD comparison\n")
        self.assert_resolves(destination, "HEAD", newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        for ref in ("main", "heads/main"):
            with self.subTest(ref=ref):
                self.assert_resolves(destination, ref, newer, offline=True)

    def test_head_file_open_uses_cached_default_commit_without_transport(self):
        destination = self.clone()
        self.commit(self.source, "new remote default version\n")

        result = self.checkout(destination, "blob/HEAD/file.txt", offline=True)

        self.assert_success(result)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertEqual((destination / "file.txt").read_text(), "initial\n")
        self.assertEqual(self.transport, [])

    def test_empty_fork_does_not_resolve_an_unrelated_local_commit_prefix(self):
        destination = self.clone()
        empty_fork = self.new_repository("empty-fork")
        self.urls["https://github.com/empty/project.git"] = empty_fork.as_uri()
        before = self.oid(destination)

        result = self.compare_ref(destination, "empty:" + before[:10])

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.oid(destination), before)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")

    def test_nonempty_fork_does_not_resolve_an_unrelated_local_commit_prefix(self):
        destination = self.clone()
        fork = self.new_repository("unrelated-fork")
        self.commit(fork, "unrelated fork history\n")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        local = self.oid(destination)

        result = self.compare_ref(destination, "alice:" + local[:10])

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.oid(destination), local)

    def test_fork_prefix_ignores_a_colliding_unrelated_local_commit(self):
        destination = self.clone()
        fork = self.new_repository("colliding-fork")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        # Fixed messages give distinct SHA-1 commits sharing the prefix f546c.
        wanted = self.empty_root_commit(fork, "fork 34609")
        unrelated = self.empty_root_commit(destination, "local 50")
        self.assertNotEqual(wanted, unrelated)
        self.assertEqual(wanted[:5], unrelated[:5])
        self.git(fork, "update-ref", "refs/heads/main", wanted)
        self.git(destination, "update-ref", "refs/heads/unrelated", unrelated)

        result = self.compare_ref(destination, "alice:" + wanted[:5])

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), wanted)
        self.assertEqual(self.oid(destination), self.initial)

    def test_fork_prefix_counts_a_commit_and_its_colliding_tag_once(self):
        destination = self.clone()
        fork = self.new_repository("tag-collision-fork")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        wanted = self.empty_root_commit(fork, "fork 34609")
        self.empty_root_commit(destination, "fork 34609")
        self.git(fork, "update-ref", "refs/heads/main", wanted)
        # This fixed tag hashes to f546ce43..., sharing the commit's prefix.
        tag_text = (
            "object %s\ntype commit\ntag local-only\n"
            "tagger Dotfiles tests <dotfiles-tests@example.invalid> 0 +0000\n\nlocal 573300\n"
        ) % wanted
        tag = self.git(destination, "hash-object", "-w", "-t", "tag", "--stdin", input=tag_text).stdout.strip()
        self.assertNotEqual(wanted, tag)
        self.assertEqual(wanted[:5], tag[:5])
        self.git(destination, "update-ref", "refs/tags/local-only", tag)

        result = self.compare_ref(destination, "alice:" + wanted[:5])

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), wanted)
        unqualified = self.compare_ref(destination, wanted[:5])
        self.assertNotEqual(unqualified.returncode, 0, unqualified.stdout)
        self.assertEqual(unqualified.stdout, "")

        # Only the local tag matches this longer prefix, not any fork object.
        self.assertNotEqual(wanted[:10], tag[:10])
        local_tag = self.compare_ref(destination, "alice:" + tag[:10])
        self.assertNotEqual(local_tag.returncode, 0, local_tag.stdout)
        self.assertEqual(local_tag.stdout, "")

    def test_fork_prefix_of_a_fetched_annotated_tag_resolves_to_its_commit(self):
        destination = self.clone()
        fork = self.new_repository("tagged-fork")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        wanted = self.commit(fork, "tagged fork commit\n")
        self.git(fork, "tag", "--annotate", "--message", "Fork release", "release")
        tag = self.oid(fork, "refs/tags/release")
        self.assertNotEqual(wanted[:10], tag[:10])

        result = self.compare_ref(destination, "alice:" + tag[:10])

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), wanted)

    def test_fork_prefix_rejects_two_colliding_fetched_commits(self):
        destination = self.clone()
        fork = self.new_repository("ambiguous-fork")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        first = self.empty_root_commit(fork, "fork 34609")
        second = self.empty_root_commit(fork, "local 50")
        self.assertNotEqual(first, second)
        self.assertEqual(first[:5], second[:5])
        self.git(fork, "update-ref", "refs/heads/main", first)
        self.git(fork, "update-ref", "refs/heads/other", second)

        result = self.compare_ref(destination, "alice:" + first[:5])

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.oid(destination), self.initial)

    def test_comparison_uses_its_own_fetch_result(self):
        destination = self.clone()
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        tip = self.commit(self.source, "topic change\n")
        compare = """function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- --stdin $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/main
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" "$argv[3]"
"""
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                result = self.fish(compare, URL, destination, "topic")
                self.assert_success(result)
                self.assertEqual(result.stdout.strip(), tip)
                self.assertEqual(self.oid(destination, "FETCH_HEAD"), self.initial)
        self.assert_resolves(destination, "topic", tip, offline=True)

    def test_checkout_caches_a_tag_that_moves_before_fetch(self):
        destination = self.clone()
        self.git(destination, "config", "remote.origin.tagOpt", "--no-tags")
        self.commit(self.source, "old release\n")
        self.git(self.source, "tag", "--annotate", "--message", "old release", "v2")
        newer = self.commit(self.source, "new release\n")
        self.git(self.source, "tag", "--annotate", "--message", "new release", "new-v2")
        tag = self.oid(self.source, "refs/tags/new-v2")

        result = self.fish("""set -g test_source "$argv[3]"
set -g test_tag "$argv[4]"
function git
    if contains -- fetch $argv; and contains -- refs/tags/v2 $argv
        command git -C "$test_source" update-ref refs/tags/v2 "$test_tag"; or return
    end
    command git $argv
end
__ghe_checkout "$argv[1]" "$argv[2]" releases/tag/v2 "" "" "" ""
""", URL, destination, self.source, tag)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assert_success(self.checkout(destination, "releases/tag/v2", offline=True))
        self.assertEqual(self.transport, [])
        cached = self.git(destination, "for-each-ref", "--format=%(objectname)", "refs/gh/compare")
        self.assertEqual(cached.stdout.strip(), tag)

    def test_delayed_pull_request_fetch_keeps_a_newer_cached_head(self):
        destination = self.clone()
        older = self.commit(self.source, "older pull request head\n")
        newer = self.commit(self.source, "newer pull request head\n")
        self.git(self.source, "update-ref", "refs/pull/7/head", older)

        result = self.fish("""set -g test_remote "$argv[1]"
set -g test_source "$argv[3]"
set -g test_newer "$argv[4]"
function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- refs/pull/7/head $argv; and not set -q test_refreshed
        set -g test_refreshed 1
        command git -C "$test_source" update-ref refs/pull/7/head "$test_newer"; or return
        __ghe_pull_request "$test_remote" "$argv[2]" 7 >/dev/null; or return
    end
end
__ghe_pull_request "$argv[1]" "$argv[2]" 7
""", URL, destination, self.source, newer)
        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), older)

        cached = self.fish('__ghe_pull_request "$argv[1]" "$argv[2]" 7',
                           URL, destination, offline=True)
        self.assert_success(cached)
        self.assertEqual(cached.stdout.strip(), newer)

    def test_fork_prefix_uses_its_own_fetched_histories(self):
        destination = self.clone()
        fork = self.new_repository("racing-fork")
        self.urls["https://github.com/alice/project.git"] = fork.as_uri()
        wanted = self.commit(fork, "fork commit\n")

        result = self.fish(
            """function git
    command git $argv; or return
    if contains -- fetch $argv; and contains -- --stdin $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin refs/heads/main
    end
end
__ghe_compare_ref "$argv[1]" "$argv[2]" "$argv[3]"
""",
            URL, destination, "alice:" + wanted[:10],
        )

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), wanted)
        self.assertEqual(self.oid(destination, "FETCH_HEAD"), self.initial)

    def test_symbolic_comparison_cache_cannot_redirect_to_unrelated_branch(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(destination, "update-ref", "-d", "refs/remotes/origin/topic")
        newer = self.commit(self.source, "unrelated main\n")
        self.git(destination, "fetch", "--quiet", self.source.as_uri(), "main")
        self.git(destination, "update-ref", "refs/heads/unrelated", newer)
        identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
        key = self.git(destination, "hash-object", "--stdin", input="refs/heads/topic\n").stdout.strip()
        cache = "refs/gh/compare/" + identity + "/by-ref/" + key
        self.git(destination, "symbolic-ref", cache, "refs/heads/unrelated")
        self.assert_resolves(destination, "topic", self.initial)
        self.assertEqual(self.oid(destination, "refs/heads/unrelated"), newer)
        self.assert_resolves(destination, "topic", self.initial, offline=True)

    def test_comparison_can_select_branch_or_tag_with_the_same_name(self):
        self.git(self.source, "tag", "release")
        newer = self.commit(self.source, "newer branch\n")
        self.git(self.source, "branch", "release")
        destination = self.clone()
        self.assert_resolves(destination, "release", newer, offline=True)
        self.assert_resolves(destination, "heads/release", newer, offline=True)
        self.assert_resolves(destination, "tags/release", self.initial, offline=True)

    def test_remote_head_and_ancestry_ignore_unpushed_local_commits(self):
        upstream = self.commit(self.source, "upstream\n")
        destination = self.clone()
        local = self.commit(destination, "local only\n")
        self.assertNotEqual(local, upstream)
        self.assert_resolves(destination, "HEAD", upstream, offline=True)
        self.assert_resolves(destination, "HEAD~1", self.initial, offline=True)

    def test_two_and_three_dot_comparisons_match_git_without_changing_checkout(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        topic = self.commit(self.source, "topic\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")
        main = self.commit(self.source, "main\n", "main.txt")
        destination = self.clone()
        before = self.git(destination, "status", "--porcelain").stdout
        for separator in ("..", "..."):
            with self.subTest(separator=separator):
                comparison = "main" + separator + "topic"
                expected = self.git(destination, "diff", main + separator + topic, "--").stdout
                result = self.fish(
                    '__ghe_compare "$argv[1]" "$argv[2]" "$argv[3]"',
                    URL, destination, comparison, offline=True,
                )
                self.assert_success(result)
                self.assertEqual(result.stdout, expected)
                self.assertTrue(self.transport)
                self.assertIn("cached", result.stderr)
                self.assertEqual(self.oid(destination), main)
                self.assertEqual(self.git(destination, "status", "--porcelain").stdout, before)

    def test_gho_uses_commit_link_for_same_named_branch_and_tag(self):
        self.git(self.source, "tag", "main")
        upstream = self.commit(self.source, "branch version\n")
        destination = self.clone()
        result = self.fish('gho "$argv[1]"', destination / "file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), "https://github.com/example/project/blob/" + upstream + "/file.txt")
        self.assertEqual(self.transport, [])

    def test_stale_default_head_alias_uses_current_fetch_mapping_offline(self):
        destination = self.clone()
        newer = self.commit(self.source, "new mapped default\n")
        self.git(destination, "config", "--replace-all", "remote.origin.fetch", "+refs/heads/*:refs/cache/origin/*")
        self.git(destination, "fetch", "--quiet", "--no-tags", "--refmap=", self.source.as_uri(),
                 "+refs/heads/main:refs/cache/origin/main")

        result = self.fish('gho "$argv[1]"', destination, offline=True)

        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), "https://github.com/example/project")
        self.assertEqual(self.transport, [])
        self.assert_resolves(destination, "HEAD", newer, offline=True)

    def test_gho_uses_commit_link_when_a_longer_tag_changes_url_interpretation(self):
        self.commit(self.source, "nested file\n", "directory/file.txt")
        self.git(self.source, "tag", "main/directory")
        destination = self.clone()
        result = self.fish('gho "$argv[1]"', destination / "directory/file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), "https://github.com/example/project/blob/" + self.oid(destination) + "/directory/file.txt")
        self.assertEqual(self.transport, [])

    def test_explicit_tag_checks_out_tag_instead_of_same_named_branch(self):
        self.git(self.source, "tag", "release")
        self.commit(self.source, "newer branch\n")
        self.git(self.source, "branch", "release")
        destination = self.clone()
        result = self.checkout(destination, "releases/tag/release", offline=True)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "HEAD", check=False).returncode, 0)
        self.assertEqual(self.transport, [])

    def test_full_commit_id_wins_over_a_branch_with_the_same_name(self):
        self.commit(self.source, "newer branch\n")
        self.git(self.source, "branch", self.initial)
        destination = self.clone()
        result = self.checkout(destination, "blob/" + self.initial + "/file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "HEAD", check=False).returncode, 0)
        self.assertEqual(self.transport, [])

    def test_short_hex_branch_stays_a_tracking_branch(self):
        self.git(self.source, "branch", "deadbeef")
        destination = self.clone()
        self.assert_success(self.checkout(destination, "blob/deadbeef/file.txt", offline=True))
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "deadbeef")
        self.assertEqual(self.git(destination, "rev-parse", "--symbolic-full-name", "@{upstream}").stdout.strip(), "refs/remotes/origin/deadbeef")
        self.assertEqual(self.transport, [])

    def test_uncached_slash_branch_opens_a_path_with_glob_characters(self):
        branch = "feature/nested"
        filename = "dir/[draft]*?.txt"
        self.git(self.source, "switch", "--quiet", "--create", branch)
        self.commit(self.source, "literal filename\n", filename)
        self.git(self.source, "switch", "--quiet", "main")
        destination = self.clone(single_branch=True)

        result = self.checkout(destination, f"blob/{branch}/{filename}")

        self.assert_success(result)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), branch)
        self.assertEqual((destination / filename).read_text(), "literal filename\n")

    def test_new_hex_branches_win_over_cached_abbreviated_commits(self):
        routes = (("2026/fix", "blob/2026/fix/file.txt"), ("2026/fix", "tree/2026/fix"),
                  ("2026", "blob/2026/file.txt"), ("2026", "tree/2026"))
        cases = [(with_paths, ref, route, self.clone())
                 for with_paths in (False, True) for ref, route in routes]
        wanted = self.commit(self.source, "new hexadecimal branches\n")
        advertised_ref = None
        for with_paths, ref, route, destination in cases:
            if ref != advertised_ref:
                if advertised_ref:
                    self.git(self.source, "branch", "--delete", "--force", advertised_ref)
                self.git(self.source, "branch", ref)
                advertised_ref = ref
            with self.subTest(with_paths=with_paths, route=route):
                unrelated = self.colliding_hex_commit(destination, with_paths=with_paths)
                self.assertTrue(unrelated.startswith("2026"))
                self.git(destination, "update-ref", "refs/heads/unrelated", unrelated)

                result = self.checkout(destination, route)

                self.assert_success(result)
                self.assertEqual(self.oid(destination), wanted)
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), ref)
                self.assertEqual((destination / "file.txt").read_text(), "new hexadecimal branches\n")
                self.assertTrue(any(call["command"] == "ls-remote" for call in self.transport))
                self.assert_success(self.checkout(destination, route, offline=True))
                self.assertEqual(self.transport, [])

    def test_cached_short_commit_fails_closed_when_remote_refs_are_unavailable(self):
        destination = self.clone()
        unrelated = self.colliding_hex_commit(destination, with_paths=True)
        self.assertTrue(unrelated.startswith("2026"))
        self.git(destination, "update-ref", "refs/heads/unrelated", unrelated)
        before = self.git(destination, "status", "--porcelain").stdout
        for route in ("blob/2026/fix/file.txt", "tree/2026/fix", "commit/2026"):
            with self.subTest(route=route):
                result = self.checkout(destination, route, offline=True)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("full 40-character commit hash", result.stderr)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
                self.assertEqual(self.git(destination, "status", "--porcelain").stdout, before)
                self.assertEqual([call["command"] for call in self.transport], ["ls-remote"])

        result = self.checkout(destination, "blob/" + unrelated + "/fix/file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), unrelated)
        self.assertEqual(self.transport, [])
        self.assert_success(self.checkout(destination, "archive/" + unrelated[:10] + ".zip", offline=True))
        self.assertEqual(self.transport, [])

    def test_cached_short_commit_checks_remote_refs_before_switching(self):
        destination = self.clone()
        result = self.checkout(destination, "blob/" + self.initial[:10] + "/file.txt")

        self.assert_success(result)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "HEAD", check=False).returncode, 0)
        self.assertEqual([call["command"] for call in self.transport], ["ls-remote"])

    def test_cached_only_resolution_keeps_short_commits_ambiguous_and_gho_offline(self):
        destination = self.clone()
        unrelated = self.colliding_hex_commit(destination, with_paths=True)
        self.git(destination, "update-ref", "refs/heads/unrelated", unrelated)
        result = self.fish('__gh_resolve "$argv[1]" blob/2026/fix/file.txt "$argv[2]" true', URL, destination, offline=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.transport, [])
        self.assertEqual(self.oid(destination), self.initial)

        self.git(destination, "switch", "--quiet", "--detach", unrelated)
        result = self.fish('gho "$argv[1]"', destination / "fix/file.txt", offline=True)
        self.assert_success(result)
        self.assertEqual(result.stdout.strip(), "https://github.com/example/project/blob/" + unrelated + "/fix/file.txt")
        self.assertEqual(self.transport, [])

    def test_missing_abbreviated_commit_is_fetched_and_detached(self):
        destination = self.clone()
        requested = self.commit(self.source, "requested commit\n")
        self.commit(self.source, "newest commit\n")
        self.assertNotEqual(self.git(destination, "cat-file", "-e", requested, check=False).returncode, 0)
        self.assert_success(self.checkout(destination, "blob/" + requested[:10] + "/file.txt"))
        self.assertEqual(self.oid(destination), requested)
        self.assertEqual((destination / "file.txt").read_text(), "requested commit\n")
        self.assertNotEqual(self.git(destination, "symbolic-ref", "--quiet", "HEAD", check=False).returncode, 0)
        self.assertTrue(any(call["command"] == "fetch" for call in self.transport))
        self.assert_success(self.checkout(destination, "blob/" + requested + "/file.txt", offline=True))
        self.assertEqual(self.transport, [])

    def test_missing_abbreviated_commit_in_shallow_clone_fetches_history(self):
        self.commit(self.source, "second\n")
        self.commit(self.source, "third\n")
        destination = self.clone(depth=1)
        self.assertEqual(self.git(destination, "rev-parse", "--is-shallow-repository").stdout.strip(), "true")
        self.assert_success(self.checkout(destination, "blob/" + self.initial[:10] + "/file.txt"))
        self.assertEqual(self.oid(destination), self.initial)
        self.assertEqual(self.git(destination, "rev-parse", "--is-shallow-repository").stdout.strip(), "false")

    def test_unknown_abbreviated_commit_has_clear_error_and_keeps_checkout(self):
        destination = self.clone()
        before = self.oid(destination)
        result = self.checkout(destination, "blob/ffffffffffff/file.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("commit", result.stderr)
        self.assertIn("longer or full", result.stderr)
        self.assertNotIn("couldn't find remote ref", result.stderr)
        self.assertEqual(self.oid(destination), before)

    def test_overlapping_fetch_mappings_do_not_invent_a_cached_branch(self):
        self.git(self.source, "branch", "-m", "main", "release/main")
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/release/*:refs/remotes/origin/*")
        self.git(destination, "config", "--add", "remote.origin.fetch",
                 "+refs/heads/*:refs/remotes/origin/*")
        self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin', destination))

        result = self.checkout(destination, "blob/main/file.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no branch, tag, or commit matches", result.stderr)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "release/main")
        self.assertNotEqual(self.git(destination, "show-ref", "--verify", "--quiet",
                                    "refs/heads/main", check=False).returncode, 0)
        self.assert_success(self.checkout(destination, "blob/release/main/file.txt", offline=True))

        self.git(self.source, "switch", "--quiet", "--create", "main")
        main = self.commit(self.source, "different main contents\n", "main-only.txt")
        result = self.checkout(destination, "blob/main/file.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fetch destination is mapped from another branch", result.stderr)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "release/main")
        self.assertNotEqual(self.git(destination, "show-ref", "--verify", "--quiet",
                                    "refs/heads/main", check=False).returncode, 0)

        self.assertNotEqual(self.compare_ref(destination, "main", offline=True).returncode, 0)
        self.assert_resolves(destination, "main", main)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        self.assert_resolves(destination, "main", main, offline=True)

        self.git(destination, "switch", "--quiet", "--create", "main", "refs/remotes/origin/main")
        self.git(destination, "config", "branch.main.remote", "origin")
        self.git(destination, "config", "branch.main.merge", "refs/heads/main")
        self.assert_success(self.checkout(destination, "blob/main/main-only.txt"))
        self.assertEqual(self.oid(destination), main)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)

    def test_nonbranch_fetch_source_does_not_claim_a_tracking_destination(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        topic = self.commit(self.source, "topic branch\n")
        self.git(self.source, "switch", "--quiet", "--create", "other", "main")
        other = self.commit(self.source, "other branch\n")
        self.git(self.source, "tag", "other-tag")
        self.git(self.source, "switch", "--quiet", "main")
        tracking = "refs/remotes/origin/topic"
        for source in ("other", "refs/tags/other-tag"):
            with self.subTest(source=source):
                destination = self.clone()
                spec = f"+{source}:{tracking}"
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", spec)
                self.git(destination, "fetch", "--quiet", self.source.as_uri(), spec)
                self.assertEqual(self.oid(destination, tracking), other)

                result = self.checkout(destination, "blob/topic/file.txt")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("mapped from another branch", result.stderr)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertEqual(self.git(destination, "config", "--get-all",
                                          "remote.origin.fetch").stdout.strip(), spec)

                self.git(destination, "config", "--add", "remote.origin.fetch",
                         f"+refs/heads/topic:{tracking}")
                self.assertNotEqual(self.compare_ref(destination, "topic", offline=True).returncode, 0)
                self.assert_resolves(destination, "topic", topic)
                self.assertEqual(self.oid(destination, tracking), other)

    def test_two_sources_do_not_claim_the_same_tracking_destination(self):
        self.git(self.source, "switch", "--quiet", "--create", "release/topic")
        release = self.commit(self.source, "release branch\n")
        self.git(self.source, "switch", "--quiet", "--create", "topic", "main")
        topic = self.commit(self.source, "topic branch\n")
        self.git(self.source, "switch", "--quiet", "main")
        tracking = "refs/remotes/origin/topic"
        for first, second in (
            (f"+refs/heads/release/topic:{tracking}", f"+refs/heads/topic:{tracking}"),
            ("+refs/heads/release/*:refs/remotes/origin/*", "+refs/heads/*:refs/remotes/origin/*"),
        ):
            with self.subTest(first=first, second=second):
                destination = self.clone(single_branch=True)
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", first)
                self.git(destination, "config", "--add", "remote.origin.fetch", second)
                self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin topic', destination))
                self.assertEqual(self.oid(destination, tracking), topic)

                result = self.checkout(destination, "blob/release/topic/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertNotEqual(self.compare_ref(destination, "release/topic", offline=True).returncode, 0)
                self.assert_resolves(destination, "release/topic", release)
                self.assertEqual(self.oid(destination, tracking), topic)

                self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/topic")
                self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin', destination))
                self.assertEqual(self.oid(destination, tracking), release)
                self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin refs/heads/topic', destination))
                self.assertEqual(self.oid(destination, tracking), topic)
                result = self.checkout(destination, "blob/release/topic/file.txt", offline=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.oid(destination), self.initial)

                self.git(destination, "config", "--replace-all", "remote.origin.fetch", first)
                self.assert_success(self.fish('git -C "$argv[1]" fetch --quiet origin', destination))
                self.assert_success(self.checkout(destination, "blob/release/topic/file.txt", offline=True))
                self.assertEqual(self.oid(destination), release)

    def test_custom_cached_fetch_destinations_set_a_working_upstream(self):
        self.git(self.source, "branch", "topic")
        for spec, tracking in (
            ("+refs/heads/*:refs/cache/origin/*", "refs/cache/origin/topic"),
            ("+refs/heads/topic:remotes/origin/topic", "refs/remotes/origin/topic"),
        ):
            with self.subTest(spec=spec):
                destination = self.clone()
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", spec)
                if tracking != "refs/remotes/origin/topic":
                    self.git(destination, "update-ref", tracking, self.initial)
                    self.git(destination, "update-ref", "-d", "refs/remotes/origin/topic")
                self.assert_success(self.checkout(destination, "blob/topic/file.txt", offline=True))
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "topic")
                self.assertEqual(self.git(destination, "rev-parse", "--symbolic-full-name", "@{upstream}").stdout.strip(), tracking)
                self.assertEqual(self.git(destination, "config", "--get-all", "remote.origin.fetch").stdout.strip(), spec)
                self.assertEqual(self.transport, [])

    def test_explicit_checkout_fetches_preserve_unrelated_tags(self):
        destinations = [self.clone(single_branch=True) for _ in range(3)]
        main = self.commit(self.source, "main branch file\n", "main.txt")
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        topic = self.commit(self.source, "topic branch file\n", "topic.txt")
        self.git(self.source, "tag", "unrelated")
        self.git(self.source, "tag", "--annotate", "--message", "release", "release")
        self.git(self.source, "switch", "--quiet", "main")
        routes = (
            ("blob/main/main.txt", main),
            ("blob/topic/topic.txt", topic),
            ("releases/tag/release", topic),
        )
        for (tail, expected), destination in zip(routes, destinations):
            with self.subTest(tail=tail):
                self.git(destination, "config", "remote.origin.tagOpt", "--tags")
                self.git(destination, "tag", "unrelated", self.initial)

                self.assert_success(self.checkout(destination, tail))

                self.assertEqual(self.oid(destination), expected)
                self.assertEqual(self.git(destination, "tag").stdout, "unrelated\n")
                self.assertEqual(self.oid(destination, "refs/tags/unrelated"), self.initial)

    def test_checkout_preserves_edits_made_during_fetch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        self.commit(self.source, "topic change\n", "topic.txt")
        self.git(self.source, "tag", "--annotate", "--message", "Release", "v2")
        self.git(self.source, "switch", "--quiet", "main")
        for tail in ("tree/topic", "releases/tag/v2"):
            with self.subTest(tail=tail):
                destination = self.clone(single_branch=True)
                result = self.fish("""function git
    command git $argv; or return
    if contains -- fetch $argv
        printf '%s\\n' 'late edit' > "$argv[2]/file.txt"
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" "$argv[3]" "" "" "" ""
""", URL, destination, tail)

                self.assert_success(result)
                self.assertIn("keeping the current ref because the checkout has local changes", result.stderr)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
                self.assertEqual((destination / "file.txt").read_text(), "late edit\n")

    def test_new_branch_starts_from_its_own_fetch_result(self):
        destination = self.clone(single_branch=True)
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        tip = self.commit(self.source, "topic change\n")
        self.git(self.source, "switch", "--quiet", "main")
        tracking = "refs/remotes/origin/topic"

        result = self.fish(
            """function git
    command git $argv; or return
    if contains -- +refs/heads/topic:refs/remotes/origin/topic $argv
        command git -C "$argv[2]" fetch --quiet --no-tags --refmap= -- origin +refs/heads/main:refs/remotes/origin/topic
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
""",
            URL, destination,
        )

        self.assert_success(result)
        self.assertEqual(self.oid(destination), tip)
        self.assertEqual(self.oid(destination, tracking), self.initial)

    def test_checkout_preserves_clean_branch_changes_during_fetch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        topic = self.commit(self.source, "topic branch\n")
        self.git(self.source, "switch", "--quiet", "main")
        for change in ("switch", "advance"):
            with self.subTest(change=change):
                destination = self.clone(single_branch=True)
                self.git(destination, "branch", "side")
                result = self.fish("""set -gx CHANGE "$argv[3]"
function git
    command git $argv; or return
    if contains -- fetch $argv
        if test "$CHANGE" = switch
            command git -C "$argv[2]" switch --quiet side
        else
            command git -C "$argv[2]" commit --quiet --allow-empty --message 'concurrent commit'
        end
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
""", URL, destination, change)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("checkout changed while fetching; skipping switch", result.stderr)
                self.assertEqual(self.oid(destination, "refs/remotes/origin/topic"), topic)
                self.assertNotEqual(self.git(destination, "show-ref", "--verify", "--quiet",
                                            "refs/heads/topic", check=False).returncode, 0)
                expected = "side" if change == "switch" else "main"
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), expected)
                if change == "switch":
                    self.assertEqual(self.oid(destination), self.initial)
                else:
                    self.assertEqual(self.oid(destination, "HEAD^"), self.initial)

    def test_checkout_preserves_a_branch_created_during_fetch(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        tip = self.commit(self.source, "topic change\n")
        self.git(self.source, "switch", "--quiet", "main")
        for target in ("refs/remotes/origin/topic", "refs/heads/topic"):
            with self.subTest(target=target):
                destination = self.clone(single_branch=True)
                self.git(destination, "config", "--add", "remote.origin.fetch", f"+refs/heads/topic:{target}")
                result = self.fish("""function git
    command git $argv; or return
    if contains -- fetch $argv
        command git -C "$argv[2]" update-ref refs/heads/topic refs/heads/main
        command git -C "$argv[2]" config branch.topic.remote private
        command git -C "$argv[2]" config branch.topic.merge refs/heads/local-topic
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" tree/topic "" "" "" ""
""", URL, destination)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertEqual(self.oid(destination, "refs/heads/topic"), self.initial)
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
                self.assertEqual(self.git(destination, "config", "branch.topic.remote").stdout.strip(), "private")
                self.assertEqual(self.git(destination, "config", "branch.topic.merge").stdout.strip(),
                                 "refs/heads/local-topic")
                if target != "refs/heads/topic":
                    self.assertEqual(self.oid(destination, target), tip)

    def test_checkout_creates_the_requested_branch_with_a_local_fetch_destination(self):
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        tip = self.commit(self.source, "topic change\n")
        self.git(self.source, "switch", "--quiet", "main")
        destination = self.clone(single_branch=True)
        self.git(destination, "config", "--add", "remote.origin.fetch", "+refs/heads/topic:refs/heads/topic")

        self.assert_success(self.checkout(destination, "blob/topic/file.txt"))

        self.assertEqual(self.oid(destination), tip)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "topic")
        self.assertEqual(self.git(destination, "config", "branch.topic.remote").stdout.strip(), "origin")
        self.assertEqual(self.git(destination, "config", "branch.topic.merge").stdout.strip(), "refs/heads/topic")

    def test_single_branch_clone_adds_tracking_for_new_branch_and_future_fetches(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone(single_branch=True)
        self.assert_success(self.checkout(destination, "blob/topic/file.txt"))
        self.assertEqual(self.git(destination, "rev-parse", "--symbolic-full-name", "@{upstream}").stdout.strip(), "refs/remotes/origin/topic")
        self.git(self.source, "switch", "--quiet", "topic")
        newer = self.commit(self.source, "new topic\n")
        self.git(destination, "-c", "url." + self.source.as_uri() + ".insteadOf=" + URL, "fetch", "--quiet", "origin")
        self.assertEqual(self.oid(destination, "@{upstream}"), newer)

    def test_excluded_branch_is_not_fetched_or_checked_out(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/topic")
        before = self.git(destination, "config", "--get-all", "remote.origin.fetch").stdout
        result = self.checkout(destination, "blob/topic/file.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("excluded", result.stderr)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual(self.git(destination, "config", "--get-all", "remote.origin.fetch").stdout, before)
        self.assertFalse(any(call["command"] == "fetch" for call in self.transport))

    def test_missing_file_pull_checks_the_fetched_path_in_a_tree_filtered_clone(self):
        self.git(self.source, "config", "uploadpack.allowFilter", "true")
        self.git(self.source, "config", "uploadpack.allowAnySHA1InWant", "true")
        destination = self.clone(object_filter="tree:0")
        newer = self.commit(self.source, "partial clone file\n", "new.txt")

        # Git's internal promisor fetches bypass the transport wrapper.
        result = self.fish("""set -g promisor_rewrite "url.$argv[3].insteadOf=$argv[1]"
function git
    if contains -- rev-parse $argv; or contains -- merge $argv
        command git -c "$promisor_rewrite" $argv
    else
        command git $argv
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" blob/main/new.txt "" "" "" ""
""", URL, destination, self.source.as_uri())

        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual((destination / "new.txt").read_text(), "partial clone file\n")

    def test_missing_file_pull_does_not_merge_a_tip_without_the_requested_path(self):
        destination = self.clone()
        newer = self.commit(self.source, "new branch file\n", "new.txt")

        result = self.checkout(destination, "blob/main/typo.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("path does not exist in this checkout", result.stderr)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertFalse((destination / "new.txt").exists())
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)
        self.assert_success(self.checkout(destination, "blob/main/new.txt"))
        self.assertEqual(self.oid(destination), newer)

    def test_missing_file_pull_uses_the_refmap_it_checked(self):
        destination = self.clone()
        self.git(destination, "switch", "--quiet", "--create", "private")
        saved = self.commit(destination, "private file\n", "saved.txt")
        self.git(destination, "switch", "--quiet", "main")
        newer = self.commit(self.source, "remote file\n", "new.txt")

        result = self.fish("""function git
    if contains -- fetch $argv
        command git -C "$argv[2]" config --replace-all remote.origin.fetch +refs/heads/main:refs/heads/private; or return
    end
    command git $argv
end
__ghe_checkout "$argv[1]" "$argv[2]" blob/main/new.txt "" "" "" ""
""", URL, destination)

        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.oid(destination, "refs/heads/private"), saved)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)

    def test_missing_file_pull_preserves_local_branch_and_tag_fetch_destinations(self):
        destinations = [self.clone(), self.clone()]
        newer = self.commit(self.source, "new branch file\n", "new.txt")
        for target, destination in zip(("refs/heads/private", "refs/tags/private"), destinations):
            with self.subTest(target=target):
                self.git(destination, "switch", "--quiet", "--create", "local-work")
                saved = self.commit(destination, "unpublished local work\n", "saved.txt")
                self.git(destination, "update-ref", target, saved)
                self.git(destination, "switch", "--quiet", "main")
                self.git(destination, "branch", "--delete", "--force", "local-work")
                self.git(destination, "config", "--replace-all", "remote.origin.fetch", f"+refs/heads/main:{target}")

                self.assert_success(self.checkout(destination, "blob/main/new.txt"))

                self.assertEqual(self.oid(destination), newer)
                self.assertEqual(self.oid(destination, target), saved)
                self.assertFalse((destination / "saved.txt").exists())

    def test_new_branch_checkout_does_not_use_a_local_branch_or_tag_as_remote_cache(self):
        destinations = [self.clone(single_branch=True) for _ in range(2)]
        self.git(self.source, "switch", "--quiet", "--create", "release/topic")
        tip = self.commit(self.source, "new topic file\n", "topic.txt")
        self.git(self.source, "switch", "--quiet", "main")
        for target, destination in zip(("refs/heads/private", "refs/tags/private"), destinations):
            with self.subTest(target=target):
                self.git(destination, "tag", "release", self.initial)
                self.git(destination, "update-ref", target, self.initial)
                self.git(destination, "config", "--add", "remote.origin.fetch", f"+refs/heads/release/topic:{target}")

                self.assert_success(self.checkout(destination, "blob/release/topic/file.txt"))

                self.assertEqual(self.oid(destination), tip)
                self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "release/topic")
                self.assertEqual(self.oid(destination, target), self.initial)

    def test_missing_file_pull_respects_sparse_rules_for_new_paths(self):
        destinations = [self.clone(), self.clone()]
        self.commit(self.source, "outside sparse selection\n", "outside/excluded.txt")
        newer = self.commit(self.source, "inside sparse selection\n", "visible/included.txt")
        cases = (
            (("--cone", "visible"), "tree/main/outside", "tree/main/visible"),
            (("--no-cone", "/visible/included.txt"), "blob/main/outside/excluded.txt",
             "blob/main/visible/included.txt"),
        )
        for (rules, excluded, included), destination in zip(cases, destinations):
            with self.subTest(rules=rules):
                self.git(destination, "sparse-checkout", "set", *rules)

                result = self.checkout(destination, excluded)

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.oid(destination), self.initial)
                self.assertFalse((destination / "visible").exists())
                self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), newer)

                self.assert_success(self.checkout(destination, included))
                self.assertEqual(self.oid(destination), newer)
                self.assertFalse((destination / "outside").exists())
                self.assertEqual((destination / "visible/included.txt").read_text(),
                                 "inside sparse selection\n")

    def test_missing_sparse_path_does_not_pull_a_tracked_file(self):
        before = self.commit(self.source, "sparse file\n", "excluded.txt")
        destination = self.clone()
        self.git(destination, "sparse-checkout", "set", "--no-cone", "/file.txt")
        self.assertFalse((destination / "excluded.txt").exists())
        self.assertEqual(self.git(destination, "status", "--porcelain").stdout, "")
        self.commit(self.source, "updated visible file\n")

        result = self.checkout(destination, "blob/main/excluded.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("path does not exist in this checkout", result.stderr)
        self.assertEqual(self.transport, [])
        self.assertEqual(self.oid(destination), before)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), before)
        self.assertEqual((destination / "file.txt").read_text(), "initial\n")

    def test_missing_file_pull_keeps_all_tracking_refs_when_one_update_fails(self):
        destination = self.clone()
        tracking = "refs/cache/origin/main"
        self.git(destination, "config", "--add", "remote.origin.fetch", f"+refs/heads/main:{tracking}")
        self.git(destination, "update-ref", tracking, self.initial)
        lock = destination / ".git" / (tracking + ".lock")
        lock.write_text("held by another process\n")
        self.commit(self.source, "new branch file\n", "new.txt")

        result = self.checkout(destination, "blob/main/new.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.oid(destination), self.initial)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        self.assertEqual(self.oid(destination, tracking), self.initial)
        self.assertFalse((destination / "new.txt").exists())

    def test_missing_file_does_not_pull_a_negatively_excluded_upstream(self):
        destination = self.clone()
        self.git(destination, "config", "--add", "remote.origin.fetch", "^refs/heads/main")
        self.commit(self.source, "new file\n", "new.txt")

        result = self.checkout(destination, "blob/main/new.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("upstream is excluded", result.stderr)
        self.assertEqual(self.transport, [])
        self.assertEqual(self.oid(destination), self.initial)
        self.assertFalse((destination / "new.txt").exists())

    def test_missing_file_does_not_pull_a_different_upstream_branch(self):
        self.git(self.source, "branch", "topic")
        self.git(self.source, "switch", "--quiet", "--create", "other")
        self.commit(self.source, "other branch only\n", "new.txt")
        self.git(self.source, "switch", "--quiet", "main")

        for upstream in ("origin/other", "other"):
            with self.subTest(upstream=upstream):
                destination = self.clone()
                if upstream == "other":
                    self.git(destination, "branch", "other", "origin/other")
                self.git(destination, "switch", "--quiet", "--create", "topic", "--track", upstream)
                self.git(destination, "reset", "--hard", self.initial)

                self.assert_success(self.checkout(destination, "blob/topic/file.txt", offline=True))
                self.assertEqual(self.transport, [])
                result = self.checkout(destination, "blob/topic/new.txt")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("upstream branch does not match the requested branch", result.stderr)
                self.assertEqual(self.transport, [])
                self.assertEqual(self.oid(destination), self.initial)
                self.assertFalse((destination / "new.txt").exists())

    def test_missing_file_does_not_fetch_a_tag_for_an_abbreviated_upstream(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+topic:refs/remotes/origin/topic")
        self.git(destination, "switch", "--quiet", "--create", "topic", "--no-track")
        self.git(destination, "config", "branch.topic.remote", "origin")
        self.git(destination, "config", "branch.topic.merge", "topic")
        self.git(self.source, "branch", "--delete", "topic")
        self.commit(self.source, "tag only\n", "new.txt")
        self.git(self.source, "tag", "topic")

        result = self.checkout(destination, "blob/topic/new.txt")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call["args"][-1] for call in self.transport], ["refs/heads/topic"])
        self.assertEqual(self.oid(destination), self.initial)
        self.assertFalse((destination / "new.txt").exists())

    def test_missing_file_does_not_merge_a_tag_for_an_abbreviated_local_upstream(self):
        destination = self.clone()
        self.git(destination, "switch", "--quiet", "--create", "topic", "--no-track")
        tagged = self.commit(destination, "tag only\n", "new.txt")
        self.git(destination, "tag", "topic", tagged)
        self.git(destination, "reset", "--hard", self.initial)
        self.git(destination, "config", "branch.topic.remote", ".")
        self.git(destination, "config", "branch.topic.merge", "topic")

        result = self.checkout(destination, "blob/refs/heads/topic/new.txt", offline=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("path does not exist in this checkout", result.stderr)
        self.assertEqual(self.transport, [])
        self.assertEqual(self.oid(destination), self.initial)
        self.assertFalse((destination / "new.txt").exists())

    def test_missing_file_does_not_pull_after_a_skipped_switch(self):
        self.git(self.source, "branch", "topic")
        self.git(self.source, "tag", "release")
        destinations = [self.clone(), self.clone()]
        self.commit(self.source, "main branch only\n", "new.txt")
        for tail, destination in zip(("blob/topic/new.txt", "blob/release/new.txt"), destinations):
            with self.subTest(tail=tail):
                dirty_file = destination / "untracked"
                dirty_file.touch()

                result = self.fish("""function git
    command git $argv; or return
    if contains -- status $argv; and test -f "$argv[2]/untracked"
        rm -- "$argv[2]/untracked"
    end
end
__ghe_checkout "$argv[1]" "$argv[2]" "$argv[3]" "" "" "" ""
""", URL, destination, tail)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("keeping the current ref", result.stderr)
                self.assertEqual(self.transport, [])
                self.assertEqual(self.oid(destination), self.initial)
                self.assertFalse((destination / "new.txt").exists())
                self.assertFalse(dirty_file.exists())

    def test_symbolic_fetch_destination_is_rejected_without_overwriting_it(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(destination, "symbolic-ref", "refs/remotes/origin/topic", "refs/remotes/origin/main")
        result = self.checkout(destination, "blob/topic/file.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic", result.stderr)
        self.assertEqual(self.git(destination, "symbolic-ref", "refs/remotes/origin/topic").stdout.strip(), "refs/remotes/origin/main")
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")

    def test_comparisons_preserve_case_folded_local_branch_and_tag_namespaces(self):
        for target in ("refs/Heads/main", "refs/Tags/local-tag"):
            with self.subTest(target=target):
                destination = self.clone()
                self.git(destination, "tag", "local-tag")
                self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                         "+refs/heads/main:" + target)
                before = self.oid(destination)
                before_tag = self.oid(destination, "refs/tags/local-tag")
                before_target = self.git(destination, "rev-parse", "--verify", "--quiet",
                                         target, check=False)
                tip = self.commit(self.source, target + "\n")

                self.assert_resolves(destination, "HEAD", tip)
                self.assertEqual(self.oid(destination), before)
                self.assertEqual(self.oid(destination, "refs/tags/local-tag"), before_tag)
                self.assertEqual(self.git(destination, "status", "--porcelain").stdout, "")
                after_target = self.git(destination, "rev-parse", "--verify", "--quiet",
                                        target, check=False)
                self.assertEqual((after_target.returncode, after_target.stdout),
                                 (before_target.returncode, before_target.stdout))

    def test_pull_handles_case_folded_checked_out_branch_destinations(self):
        for index, target in enumerate(("refs/Heads/main", "refs/heads/Main")):
            with self.subTest(target=target):
                destination = self.clone()
                self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                         "+refs/heads/main:" + target)
                filename = "new-%d.txt" % index
                newer = self.commit(self.source, "new file\n", filename)

                result = self.fish('__ghe_pull "$argv[1]" "$argv[2]" main "$argv[3]"', destination, URL, filename)

                self.assert_success(result)
                self.assertEqual(self.oid(destination), newer)
                self.assertTrue((destination / filename).is_file())
                self.assertEqual((destination / filename).read_text(), "new file\n")
                self.assertEqual(self.git(destination, "status", "--porcelain").stdout, "")

    def test_pull_does_not_update_another_branch_through_a_symbolic_fetch_destination(self):
        destination = self.clone()
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        newer = self.commit(self.source, "topic file\n", "topic-only.txt")
        self.git(destination, "config", "--replace-all", "remote.origin.fetch",
                 "+refs/heads/topic:refs/remotes/origin/HEAD")
        self.git(destination, "switch", "--quiet", "--create", "topic")
        self.git(destination, "config", "branch.topic.remote", "origin")
        self.git(destination, "config", "branch.topic.merge", "refs/heads/topic")

        self.assert_success(self.checkout(destination, "blob/topic/topic-only.txt"))

        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.oid(destination, "refs/remotes/origin/main"), self.initial)
        alias = self.git(destination, "symbolic-ref", "refs/remotes/origin/HEAD").stdout.strip()
        self.assertEqual(alias, "refs/remotes/origin/main")

    def test_pull_preserves_tracking_refs_with_ambiguous_fetch_mappings(self):
        self.git(self.source, "branch", "-m", "main", "release/topic")
        self.git(self.source, "switch", "--quiet", "--create", "topic")
        newer = self.commit(self.source, "topic file\n", "topic-only.txt")
        self.git(self.source, "switch", "--quiet", "release/topic")
        mappings = (
            (
                "+release/topic:refs/remotes/origin/topic",
                "+refs/heads/*:refs/remotes/origin/*",
                "refs/heads/topic", "refs/remotes/origin/topic",
            ),
            (
                "+refs/heads/release/topic:refs/remotes/origin/Topic",
                "+refs/heads/*:refs/remotes/origin/*",
                "refs/heads/topic", "refs/remotes/origin/Topic",
            ),
            (
                "+refs/heads/release/*:refs/remotes/origin/Topic/*",
                "+refs/heads/*:refs/remotes/origin/topic/*",
                "refs/heads/topic", "refs/remotes/origin/Topic/topic",
            ),
            (
                "+release/topic:refs/remotes/origin/topic",
                "+topic:refs/remotes/origin/topic",
                "topic", "refs/remotes/origin/topic",
            ),
            (
                "+release/topic:refs/remotes/origin/Topic",
                "+topic:refs/remotes/origin/topic",
                "topic", "refs/remotes/origin/Topic",
            ),
        )
        for first, second, upstream, tracking in mappings:
            for packed in (False, True):
                with self.subTest(first=first, second=second, packed=packed):
                    destination = self.clone()
                    self.git(destination, "update-ref", "-d", "refs/remotes/origin/topic")
                    self.git(destination, "update-ref", tracking, self.initial)
                    if packed:
                        self.git(destination, "pack-refs", "--all", "--prune")
                    self.git(destination, "config", "--replace-all", "remote.origin.fetch", first)
                    self.git(destination, "config", "--add", "remote.origin.fetch", second)
                    self.git(destination, "switch", "--quiet", "--create", "topic", self.initial)
                    self.git(destination, "config", "branch.topic.remote", "origin")
                    self.git(destination, "config", "branch.topic.merge", upstream)

                    self.assert_success(self.checkout(destination, "blob/topic/topic-only.txt"))

                    self.assertEqual(self.oid(destination), newer)
                    self.assertEqual(self.oid(destination, tracking), self.initial)
                    refs = self.git(destination, "for-each-ref", "--ignore-case",
                                    "--format=%(refname)", tracking).stdout.splitlines()
                    self.assertEqual(refs, [tracking])

    def test_pull_can_fast_forward_when_fetch_mapping_targets_current_branch(self):
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/heads/main")
        newer = self.commit(self.source, "new upstream\n")
        result = self.fish('__ghe_pull "$argv[1]" "$argv[2]" main file.txt', destination, URL)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual((destination / "file.txt").read_text(), "new upstream\n")


if __name__ == "__main__":
    unittest.main()
