import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PickerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="fzf-paths-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.binary = cls.root / "fzf-paths"
        subprocess.run(
            ["rustc", "--edition=2021", "-O", str(Path(__file__).with_name("main.rs")), "-o", str(cls.binary)],
            check=True,
        )
        cls.owner = cls.root / "owner"
        cls.repo = cls.owner / "project"
        cls.local = cls.root / "local"
        cls.repo.mkdir(parents=True)
        cls.local.mkdir()
        env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        subprocess.run(["git", "init", "-q", str(cls.repo)], env=env, check=True)
        for name in ["tracked", "nested/child", ".hidden", "line\nbreak/end", "removed", "node_modules/tracked"]:
            path = cls.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        subprocess.run(["git", "-C", str(cls.repo), "add", "--", "."], env=env, check=True)
        (cls.repo / "removed").unlink()
        (cls.repo / "untracked").write_text("untracked")
        for name in ["file", "executable", "$literal", "~literal", "dir/child", "node_modules/excluded", ".git/excluded"]:
            path = cls.local / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        (cls.local / "executable").chmod(0o700)
        (cls.local / "linked").symlink_to(cls.local / "dir", target_is_directory=True)
        (cls.local / "loop").symlink_to(cls.local, target_is_directory=True)
        (cls.local / "broken").symlink_to(cls.local / "missing")

    def pick(self, *, cwd=None, directory=".", owner=None, kind="-fd", keep=False, aliases=(), pwd=None):
        cwd = cwd or self.local
        result = subprocess.run(
            [str(self.binary), directory, str(self.owner if owner is None else owner), kind,
             "true" if keep else "false", *map(str, aliases)],
            cwd=cwd,
            env={**os.environ, "PWD": str(pwd or cwd)},
            capture_output=True,
            check=True,
            timeout=10,
        )
        self.assertEqual(result.stderr, b"")
        return [os.fsdecode(path) for path in result.stdout.split(b"\0") if path]

    def test_local_paths_are_first_and_unique(self):
        paths = self.pick()
        first_global = paths.index(str(self.repo))
        self.assertGreater(first_global, 0)
        self.assertTrue(all(not path.startswith("/") for path in paths[:first_global]))
        self.assertEqual(len(paths), len(set(paths)))

    def test_tracked_files_and_parents(self):
        paths = self.pick()
        for name in ["tracked", "nested", "nested/child", ".hidden", "line\nbreak/end", "node_modules/tracked"]:
            with self.subTest(name=name):
                self.assertIn(str(self.repo / name), paths)
        for name in ["untracked", "removed"]:
            self.assertNotIn(str(self.repo / name), paths)

    def test_longest_alias_and_raw_local_copy(self):
        paths = self.pick(cwd=self.repo, aliases=("$owner", self.owner, "$project", self.repo))
        self.assertIn("$project/nested/child", paths)
        self.assertIn("nested/child", paths)
        self.assertLess(paths.index("nested/child"), paths.index("$project/nested/child"))
        self.assertFalse(any(path.startswith("$owner/project") for path in paths))

    def test_directories_only(self):
        paths = self.pick(kind="-d")
        self.assertIn("dir", paths)
        self.assertIn(str(self.repo / "nested"), paths)
        self.assertTrue(all((self.local / path).is_dir() for path in paths))

    def test_executables_keep_dot_prefix(self):
        paths = self.pick(kind="-fdx", keep=True)
        self.assertIn("./executable", paths)
        self.assertNotIn("./file", paths)
        self.assertTrue(all(os.access(self.local / path, os.X_OK) for path in paths))

    def test_literal_prefixes_are_escaped(self):
        paths = self.pick()
        self.assertIn("./$literal", paths)
        self.assertIn("./~literal", paths)

    def test_ignored_directories_broken_links_and_cycles(self):
        paths = self.pick(owner="")
        self.assertNotIn("node_modules", paths)
        self.assertNotIn(".git", paths)
        self.assertNotIn("broken", paths)
        self.assertIn("linked/child", paths)
        self.assertIn("loop", paths)
        self.assertFalse(any(path.startswith("loop/") for path in paths))

    def test_empty_or_missing_owner(self):
        self.assertEqual(self.pick(owner=""), self.pick(owner=str(self.root / "absent")))

    def test_logical_working_directory(self):
        link = self.root / "logical"
        link.symlink_to(self.local, target_is_directory=True)
        self.assertEqual(self.pick(), self.pick(pwd=link))

    def test_invalid_arguments(self):
        result = subprocess.run([str(self.binary)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
