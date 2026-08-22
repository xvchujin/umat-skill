#!/usr/bin/env python3
"""Validate the copyright-safe public UMAT Skill release."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


EXPECTED_SKILLS = sorted(
    {
        "abaqus-tensor-voigt-adapter",
        "constitutive-domain-stabilization-audit",
        "cpa-implicit-return-mapping",
        "ddsdde-finite-difference-audit",
        "explicit-adaptive-substepping",
        "explicit-alpha-yield-intersection",
        "explicit-yield-drift-correction",
        "hill48-yield-calibration-applicability-audit",
        "j2-isotropic-hardening-radial-return",
        "softening-objectivity-audit",
        "tsai-wu-damage-state-machine",
        "tsai-wu-parameter-audit",
        "umat-failure-cutback-protocol",
        "umat-hierarchical-validation",
        "umat-props-statev-contract",
        "umat-semantic-debugging",
        "umat-transactional-state-update",
        "umat-update-mechanism-router",
        "wood-cdm-abaqus-nonlocal-architecture-router",
        "wood-cdm-damaged-operator-closure",
        "wood-cdm-mechanism-router",
        "wood-cdm-multimode-state-machine",
        "wood-cdm-spatial-regularization-router",
        "wood-cdm-thermodynamic-closure",
        "wood-fiber-orientation-field-pipeline",
    }
)

ROOT_FILES = {
    ".gitattributes",
    ".gitignore",
    "CHANGELOG.md",
    "PUBLICATION_POLICY.md",
    "README.md",
    "SKILL_MANIFEST.tsv",
    "tools/update-skill-manifest.ps1",
    "tools/update_skill_manifest.py",
    "tools/verify-public-release.ps1",
    "tools/verify_public_release.py",
}

FORBIDDEN_EXTENSIONS = {
    ".pdf", ".caj", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
    ".png", ".jpg", ".jpeg", ".gif", ".tif", ".tiff", ".bmp", ".svg",
    ".mp3", ".wav", ".mp4", ".avi", ".mov", ".mkv",
    ".zip", ".7z", ".rar", ".tar", ".gz",
    ".for", ".f", ".f90", ".obj", ".dll", ".exe",
    ".inp", ".odb", ".cae", ".jnl", ".msg", ".dat", ".sta", ".log",
}

FORBIDDEN_PATH = re.compile(
    r"(^|/)(\.build|transcripts?|corpus|candidates?|source|extensions?|"
    r"preprocessed|rejected|stage\d[^/]*)(/|$)",
    re.IGNORECASE,
)

CONTENT_CHECKS = (
    (re.compile(r"^\s*>\s", re.MULTILINE), "Markdown quotation block"),
    (re.compile(r"\.\.[\\/]"), "parent-directory link"),
    (re.compile(r"\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b"), "media timecode"),
    (
        re.compile(r"jishulink|技术邻|transcripts?|逐字稿|核对版视频", re.IGNORECASE),
        "private source marker",
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def discover_skill_directories(repository: Path) -> list[Path]:
    return sorted(
        (
            path
            for path in repository.iterdir()
            if path.is_dir() and (path / "SKILL.md").is_file()
        ),
        key=lambda path: path.name.lower(),
    )


def allowed_public_files() -> set[str]:
    allowed = set(ROOT_FILES)
    for skill in EXPECTED_SKILLS:
        allowed.add(f"{skill}/SKILL.md")
        allowed.add(f"{skill}/agents/openai.yaml")
    return allowed


def validate_skill(directory: Path, errors: list[str]) -> None:
    skill_path = directory / "SKILL.md"
    text = skill_path.read_text(encoding="utf-8")
    relative_skill = f"{directory.name}/SKILL.md"

    frontmatter = re.match(r"\A---\r?\n(.*?)\r?\n---", text, re.DOTALL | re.MULTILINE)
    name_match = re.search(r"^name:\s*([^\r\n]+)$", text, re.MULTILINE)
    description_match = re.search(r"^description:\s*\|\s*$", text, re.MULTILINE)
    if not frontmatter:
        errors.append(f"Missing YAML frontmatter: {relative_skill}")
    if not name_match or name_match.group(1).strip() != directory.name:
        errors.append(f"Frontmatter name mismatch: {relative_skill}")
    if not description_match:
        errors.append(f"Missing block description: {relative_skill}")
    if frontmatter:
        keys = re.findall(r"^([a-zA-Z0-9_-]+):", frontmatter.group(1), re.MULTILINE)
        extras = [key for key in keys if key not in {"name", "description"}]
        if extras:
            errors.append(f"Unexpected frontmatter keys in {relative_skill}: {', '.join(extras)}")
    if len(text.splitlines()) > 500:
        errors.append(f"SKILL.md exceeds 500 lines: {relative_skill}")

    files_within_skill = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file()
    }
    unexpected = sorted(files_within_skill - {"SKILL.md", "agents/openai.yaml"})
    for path in unexpected:
        errors.append(f"Unexpected public skill file: {directory.name}/{path}")

    for pattern, label in CONTENT_CHECKS:
        if pattern.search(text):
            errors.append(f"{label}: {relative_skill}")

    if not re.search(r"^## 相关 skills\s*$.*?(?=^## |\Z)", text, re.DOTALL | re.MULTILINE):
        errors.append(f"Missing routing section: {relative_skill}")

    agent_path = directory / "agents" / "openai.yaml"
    relative_agent = f"{directory.name}/agents/openai.yaml"
    if not agent_path.is_file():
        errors.append(f"Missing agents/openai.yaml: {directory.name}")
        return
    agent_text = agent_path.read_text(encoding="utf-8")
    display = re.search(r'^  display_name:\s*"([^"]+)"\s*$', agent_text, re.MULTILINE)
    short = re.search(r'^  short_description:\s*"([^"]+)"\s*$', agent_text, re.MULTILINE)
    prompt = re.search(r'^  default_prompt:\s*"([^"]+)"\s*$', agent_text, re.MULTILINE)
    if not display:
        errors.append(f"Invalid display_name: {relative_agent}")
    if not short or not 25 <= len(short.group(1)) <= 64:
        errors.append(f"short_description must be 25-64 chars: {relative_agent}")
    if not prompt or f"${directory.name}" not in prompt.group(1):
        errors.append(f"default_prompt must mention ${directory.name}: {relative_agent}")


def expected_manifest_lines(repository: Path, directories: list[Path]) -> list[str]:
    files: list[Path] = []
    for directory in directories:
        for candidate in (directory / "SKILL.md", directory / "agents" / "openai.yaml"):
            if candidate.is_file():
                files.append(candidate)
    files.sort(key=lambda path: path.relative_to(repository).as_posix().lower())
    lines = ["path\tsize_bytes\tsha256"]
    for path in files:
        relative = path.relative_to(repository).as_posix()
        lines.append(f"{relative}\t{path.stat().st_size}\t{sha256(path)}")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repository_root",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    args = parser.parse_args()
    repository = args.repository_root.resolve(strict=True)
    errors: list[str] = []

    directories = discover_skill_directories(repository)
    actual_skills = [directory.name for directory in directories]
    missing = sorted(set(EXPECTED_SKILLS) - set(actual_skills))
    unexpected = sorted(set(actual_skills) - set(EXPECTED_SKILLS))
    if missing:
        errors.append(f"Missing skills: {', '.join(missing)}")
    if unexpected:
        errors.append(f"Unexpected skills: {', '.join(unexpected)}")

    allowed = allowed_public_files()
    all_files = sorted(
        (
            path
            for path in repository.rglob("*")
            if path.is_file() and ".git" not in path.relative_to(repository).parts
        ),
        key=lambda path: path.relative_to(repository).as_posix().lower(),
    )
    if (repository / ".build").exists():
        errors.append("Build directory is not permitted in a public release: .build")

    for path in all_files:
        relative = path.relative_to(repository).as_posix()
        if relative not in allowed:
            errors.append(f"Unexpected public release file: {relative}")
        if path.suffix.lower() in FORBIDDEN_EXTENSIONS:
            errors.append(f"Forbidden extension: {relative}")
        if FORBIDDEN_PATH.search(relative):
            errors.append(f"Forbidden path segment: {relative}")
        if path.stat().st_size > 262_144:
            errors.append(f"File exceeds 256 KiB: {relative}")
        if path.is_symlink():
            errors.append(f"Links are not allowed: {relative}")
        if b"\0" in path.read_bytes():
            errors.append(f"NUL byte or binary content: {relative}")

    for directory in directories:
        validate_skill(directory, errors)

    manifest = repository / "SKILL_MANIFEST.tsv"
    expected_lines = expected_manifest_lines(repository, directories)
    if not manifest.is_file():
        errors.append("Missing SKILL_MANIFEST.tsv")
    else:
        actual_lines = manifest.read_text(encoding="utf-8").splitlines()
        if actual_lines != expected_lines:
            errors.append(
                "Manifest content mismatch: run tools/update_skill_manifest.py before validation"
            )

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"PUBLIC_RELEASE_VALIDATION=FAIL ERRORS={len(errors)}", file=sys.stderr)
        return 1

    print("PUBLIC_RELEASE_VALIDATION=PASS")
    print(f"SKILLS={len(actual_skills)}")
    print(f"FILES={len(all_files)}")
    print(f"MANIFEST_FILES={len(expected_lines) - 1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
