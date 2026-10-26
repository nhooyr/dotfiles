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

    def oid(self, repository, ref="HEAD"):
        return self.git(repository, "rev-parse", "--verify", ref).stdout.strip()

    def clone(self, *, single_branch=False, depth=None):
        self.counter += 1
        destination = self.directory / ("checkout" + str(self.counter))
        options = ["--quiet", "--no-tags"] if single_branch else ["--quiet"]
        if single_branch:
            options.extend(("--single-branch", "--branch=main"))
        if depth:
            options.append("--depth=" + str(depth))
        self.git(self.directory, "clone", *options, self.source.as_uri(), str(destination))
        self.git(destination, "remote", "set-url", "origin", URL)
        self.git(destination, "config", "user.name", "Dotfiles tests")
        self.git(destination, "config", "user.email", "dotfiles-tests@example.invalid")
        return destination

    def empty_checkout(self):
        destination = self.new_repository("empty")
        self.git(destination, "remote", "add", "origin", URL)
        return destination

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
            source_ref = "refs/" + namespace + "/topic"
            for cache_format in ("hierarchical", "escaped", "hashed"):
                with self.subTest(namespace=namespace, cache_format=cache_format):
                    destination = self.empty_checkout()
                    self.git(destination, "fetch", "--quiet", "--no-tags", self.source.as_uri(), "main")
                    identity = self.git(destination, "hash-object", "--stdin", input="example/project\n").stdout.strip()
                    key = {
                        "hierarchical": source_ref,
                        "escaped": "refs_2F_" + namespace + "_2F_topic",
                        "hashed": "by-ref/" + self.git(destination, "hash-object", "--stdin", input=source_ref + "\n").stdout.strip(),
                    }[cache_format]
                    self.git(destination, "update-ref", "refs/gh/compare/" + identity + "/" + key, self.initial)
                    self.assert_resolves(destination, namespace + "/topic", self.initial, offline=True)

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

    def test_cached_comparison_commit_ids_do_not_attempt_transport(self):
        destination = self.clone()
        for ref in (self.initial, self.initial[:10]):
            for offline in (False, True):
                with self.subTest(ref=ref, offline=offline):
                    result = self.compare_ref(destination, ref, offline=offline)
                    self.assert_success(result)
                    self.assertEqual(result.stdout.strip(), self.initial)
                    self.assertEqual(self.transport, [])

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
        self.assert_success(self.checkout(destination, "blob/" + requested[:10] + "/file.txt", offline=True))
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

    def test_symbolic_fetch_destination_is_rejected_without_overwriting_it(self):
        self.git(self.source, "branch", "topic")
        destination = self.clone()
        self.git(destination, "symbolic-ref", "refs/remotes/origin/topic", "refs/remotes/origin/main")
        result = self.checkout(destination, "blob/topic/file.txt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic", result.stderr)
        self.assertEqual(self.git(destination, "symbolic-ref", "refs/remotes/origin/topic").stdout.strip(), "refs/remotes/origin/main")
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")

    def test_pull_can_fast_forward_when_fetch_mapping_targets_current_branch(self):
        destination = self.clone()
        self.git(destination, "config", "--replace-all", "remote.origin.fetch", "+refs/heads/main:refs/heads/main")
        newer = self.commit(self.source, "new upstream\n")
        result = self.fish('__ghe_pull "$argv[1]" "$argv[2]"', destination, URL)
        self.assert_success(result)
        self.assertEqual(self.oid(destination), newer)
        self.assertEqual(self.git(destination, "branch", "--show-current").stdout.strip(), "main")
        self.assertEqual((destination / "file.txt").read_text(), "new upstream\n")


if __name__ == "__main__":
    unittest.main()
