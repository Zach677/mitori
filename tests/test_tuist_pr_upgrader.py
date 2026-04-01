import importlib.util
import os
import sys
import textwrap
import tempfile
from pathlib import Path
import unittest

SAMPLE_EXTEND = textwrap.dedent("""
# Config

```toml
scan_roots = ["/tmp/repos"]
allow_push = false
allow_pr = false

[repos.mitori]
path = "/tmp/repos/mitori"
verify_commands = ["mise run test-macos"]
```
""")


def load_module():
    spec = importlib.util.spec_from_file_location(
        "tuist_pr_upgrader",
        Path(__file__).resolve().parent.parent
        / "skills"
        / "tuist-pr-upgrader"
        / "scripts"
        / "tuist_pr_upgrader.py",
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TuistPrUpgraderTests(unittest.TestCase):
    def test_extract_toml_block_from_extend(self):
        module = load_module()
        block = module.extract_toml_block(SAMPLE_EXTEND)
        self.assertIn("scan_roots", block)
        self.assertIn("allow_push = false", block)
        self.assertNotIn("```toml", block)
        self.assertNotIn("```", block)

    def test_load_extend_config_parses_values(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmpdir:
            extend_path = Path(tmpdir) / "EXTEND.md"
            extend_path.write_text(SAMPLE_EXTEND)
            config = module.load_extend_config(extend_path)

        self.assertEqual(config.scan_roots, [Path("/tmp/repos")])
        self.assertFalse(config.allow_push)
        self.assertFalse(config.allow_pr)
        self.assertEqual(config.include_repos, [])
        self.assertEqual(config.exclude_repos, [])
        self.assertIn("mitori", config.repos)
        repo = config.repos["mitori"]
        self.assertEqual(repo.name, "mitori")
        self.assertEqual(repo.path, Path("/tmp/repos/mitori"))
        self.assertEqual(repo.verify_commands, ["mise run test-macos"])
        self.assertIsNone(repo.base_branch)

    def test_configured_extend_file_paths_respects_order(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_root = Path(tmpdir)
            local_extend_dir = tmp_root / ".zach-skills/tuist-pr-upgrader"
            local_extend_dir.mkdir(parents=True)
            local_extend = local_extend_dir / "EXTEND.md"
            local_extend.write_text("local")

            xdg_base = tmp_root / "xdg"
            xdg_extend_dir = xdg_base / "zach-skills/tuist-pr-upgrader"
            xdg_extend_dir.mkdir(parents=True)
            xdg_extend = xdg_extend_dir / "EXTEND.md"
            xdg_extend.write_text("xdg")

            home_base = tmp_root / "home"
            home_extend_dir = home_base / ".zach-skills/tuist-pr-upgrader"
            home_extend_dir.mkdir(parents=True)
            home_extend = home_extend_dir / "EXTEND.md"
            home_extend.write_text("home")

            original_home = os.environ.get("HOME")
            original_xdg = os.environ.get("XDG_CONFIG_HOME")
            os.environ["HOME"] = str(home_base)
            os.environ["XDG_CONFIG_HOME"] = str(xdg_base)

            try:
                paths = module.configured_extend_file_paths(cwd=tmp_root)
            finally:
                if original_home is not None:
                    os.environ["HOME"] = original_home
                else:
                    os.environ.pop("HOME", None)
                if original_xdg is not None:
                    os.environ["XDG_CONFIG_HOME"] = original_xdg
                else:
                    os.environ.pop("XDG_CONFIG_HOME", None)

        self.assertEqual(paths, [local_extend, xdg_extend, home_extend])

    def test_is_tuist_candidate_requires_all_files(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "mitori"
            repo.mkdir()
            for name in ["Project.swift", "Tuist.swift", "mise.toml"]:
                (repo / name).write_text("")
            self.assertTrue(module.is_tuist_candidate(repo))

            missing = Path(tmpdir) / "missing"
            missing.mkdir()
            (missing / "Project.swift").write_text("")
            (missing / "Tuist.swift").write_text("")
            self.assertFalse(module.is_tuist_candidate(missing))

    def test_discover_candidate_repos_filters_non_candidates(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmpdir:
            scan_root = Path(tmpdir) / "scan"
            scan_root.mkdir()

            good = scan_root / "good"
            good.mkdir()
            for name in ["Project.swift", "Tuist.swift", "mise.toml"]:
                (good / name).write_text("")

            bad = scan_root / "bad"
            bad.mkdir()
            (bad / "Project.swift").write_text("")
            (bad / "Tuist.swift").write_text("")

            candidates = module.discover_candidate_repos([scan_root])

        self.assertIn(good, candidates)
        self.assertNotIn(bad, candidates)
        self.assertEqual(len(candidates), 1)


if __name__ == "__main__":
    unittest.main()
