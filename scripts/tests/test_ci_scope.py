import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("scope", Path(__file__).parents[1] / "ci-scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTests(unittest.TestCase):
    def test_platform_and_shared_boundaries(self):
        cases = {
            "docs/TESTING.md": set(),
            "docs/specs/data-model.md": {"ios", "android"},
            "android/app/src/main/App.kt": {"android"},
            "AI 記帳/Services/BackupManager.swift": {"ios"},
            "AI 記帳Tests/NewTests.swift": {"ios"},
            "Localizable.xcstrings": {"ios"},
            ".github/workflows/android-ci.yml": {"android"},
            ".github/workflows/ios-ci.yml": {"ios"},
            "scripts/ci-scope.py": {"ios", "android"},
            "scripts/tests/test_ci_scope.py": {"ios", "android"},
            "unknown/new-input": {"ios", "android"},
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(scope.platforms(path), expected)

    def test_real_git_diff_excludes_new_base_work_and_includes_deleted_renamed_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args], stderr=subprocess.DEVNULL)
            git("init", "-b", "main")
            git("config", "user.email", "ci@example.invalid")
            git("config", "user.name", "CI test")
            (root / "old.swift").write_text("old")
            git("add", ".")
            git("commit", "-m", "base")
            before = git("rev-parse", "HEAD").decode().strip()
            git("checkout", "-b", "topic")
            (root / "docs").mkdir()
            git("mv", "old.swift", "docs/old.md")
            git("commit", "-am", "rename")
            head = git("rev-parse", "HEAD").decode().strip()
            git("checkout", "main")
            (root / "base-only").write_text("unrelated")
            git("add", ".")
            git("commit", "-m", "base advanced")
            base = git("rev-parse", "HEAD").decode().strip()
            event = {"pull_request": {"base": {"sha": base}, "head": {"sha": head}}}
            expected = ["docs/old.md", "old.swift"]
            self.assertEqual(scope.changed_paths(event, git), expected)
            self.assertEqual(scope.changed_paths({"before": before, "after": head}, git), expected)
            self.assertIsNone(scope.changed_paths({"before": "0" * 40, "after": head}, git))
            self.assertEqual(scope.changed_paths({"before": head, "after": head}, git), [])
            with self.assertRaises(subprocess.CalledProcessError):
                scope.changed_paths({"before": "missing-ref", "after": head}, git)


if __name__ == "__main__":
    unittest.main()
