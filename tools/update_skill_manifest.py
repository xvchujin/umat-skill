#!/usr/bin/env python3
"""Generate the stable public Skill file manifest."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def discover_manifest_files(repository: Path) -> list[Path]:
    files: list[Path] = []
    for directory in sorted(repository.iterdir(), key=lambda path: path.name.lower()):
        if not directory.is_dir() or not (directory / "SKILL.md").is_file():
            continue
        for candidate in (directory / "SKILL.md", directory / "agents" / "openai.yaml"):
            if candidate.is_file():
                files.append(candidate)
    return sorted(files, key=lambda path: path.relative_to(repository).as_posix().lower())


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
    files = discover_manifest_files(repository)
    lines = ["path\tsize_bytes\tsha256"]
    for path in files:
        relative = path.relative_to(repository).as_posix()
        lines.append(f"{relative}\t{path.stat().st_size}\t{sha256(path)}")

    manifest = repository / "SKILL_MANIFEST.tsv"
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"MANIFEST_FILES={len(files)}")
    print(f"MANIFEST_PATH={manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
