from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import tomllib


@dataclass
class RepoConfig:
    name: str
    path: Path
    verify_commands: list[str]
    base_branch: str | None = None


@dataclass
class ExtendConfig:
    scan_roots: list[Path] = field(default_factory=list)
    include_repos: list[str] = field(default_factory=list)
    exclude_repos: list[str] = field(default_factory=list)
    allow_push: bool = False
    allow_pr: bool = False
    repos: dict[str, RepoConfig] = field(default_factory=dict)


def configured_extend_file_paths(*, cwd: Path | None = None) -> list[Path]:
    base_dir = (cwd or Path.cwd())
    home = Path(os.environ.get("HOME", Path.home()))
    xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))

    candidates = [
        base_dir / ".zach-skills/tuist-pr-upgrader/EXTEND.md",
        xdg_config / "zach-skills/tuist-pr-upgrader/EXTEND.md",
        home / ".zach-skills/tuist-pr-upgrader/EXTEND.md",
    ]

    return [path for path in candidates if path.exists()]


def extract_toml_block(markdown: str) -> str:
    in_block = False
    lines: list[str] = []

    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        if not in_block and line == "```toml":
            in_block = True
            continue
        if in_block and line == "```":
            break
        if in_block:
            lines.append(raw_line)

    if not lines:
        raise ValueError("no toml block found")

    return "\n".join(lines).strip()


def load_extend_config(path: Path) -> ExtendConfig:
    text = path.read_text()
    block = extract_toml_block(text)
    payload = tomllib.loads(block)

    return ExtendConfig(
        scan_roots=[Path(item) for item in payload.get("scan_roots", [])],
        include_repos=list(payload.get("include_repos", [])),
        exclude_repos=list(payload.get("exclude_repos", [])),
        allow_push=bool(payload.get("allow_push", False)),
        allow_pr=bool(payload.get("allow_pr", False)),
        repos=_build_repo_configs(payload.get("repos", {})),
    )


def _build_repo_configs(raw_repos: dict[str, dict]) -> dict[str, RepoConfig]:
    configs: dict[str, RepoConfig] = {}

    for name, raw_config in raw_repos.items():
        configs[name] = RepoConfig(
            name=name,
            path=Path(raw_config["path"]),
            verify_commands=list(raw_config.get("verify_commands", [])),
            base_branch=raw_config.get("base_branch"),
        )

    return configs


def is_tuist_candidate(path: Path) -> bool:
    if not path.is_dir():
        return False

    required = ["Project.swift", "Tuist.swift", "mise.toml"]
    return all((path / name).is_file() for name in required)


def discover_candidate_repos(scan_roots: list[Path]) -> list[Path]:
    candidates: list[Path] = []

    for root in scan_roots:
        if not root.exists() or not root.is_dir():
            continue

        for entry in root.iterdir():
            if entry.is_dir() and is_tuist_candidate(entry):
                candidates.append(entry)

    return candidates
