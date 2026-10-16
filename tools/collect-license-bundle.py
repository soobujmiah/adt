#!/usr/bin/env python3
"""Attach ADT scope notices and license texts from the exact AOSP build tree."""

# Copyright (c) 2026 Sobuj Miah
# PolyForm Noncommercial 1.0.0 plus the project-specific terms in LICENSE-SCOPE.md.

from __future__ import annotations

import argparse
import os
import shutil
from pathlib import Path


LICENSE_NAMES = ("LICENSE", "LICENCE", "COPYING", "NOTICE")


def is_license_name(name: str) -> bool:
    upper = name.upper()
    return any(
        upper == base or upper.startswith(base + ".") or upper.startswith(base + "-")
        for base in LICENSE_NAMES
    ) or upper == "LICENSES" or upper == "LICENCES" or upper.startswith(("LICENSES.", "LICENCES."))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="AOSP source tree")
    parser.add_argument("--package", type=Path, required=True, help="Package directory")
    args = parser.parse_args()
    source = args.source.resolve()
    package = args.package.resolve()
    if not source.is_dir() or not package.is_dir():
        raise SystemExit("source and package must be existing directories")

    repo = Path(__file__).resolve().parents[1]
    for name in (
        "LICENSE", "LICENSE-APACHE-2.0", "LICENSE-SCOPE.md",
        "LICENSE-COMMERCIAL-ADDENDUM.md",
        "NOTICE", "THIRD_PARTY_NOTICES.md",
    ):
        shutil.copy2(repo / name, package / name)

    destination = package / "upstream-licenses" / "aosp"
    collected: list[str] = []
    for directory in sorted(source.iterdir()):
        if not directory.is_dir() or directory.name == ".repo":
            continue
        for current, dirs, files in os.walk(directory):
            dirs[:] = sorted(d for d in dirs if d != ".git")
            for filename in sorted(files):
                if not is_license_name(filename):
                    continue
                original = Path(current) / filename
                relative = original.relative_to(source).as_posix()
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, target)
                collected.append(f"aosp/{relative}")

    if not collected:
        raise SystemExit("no AOSP license/notice files were found; refusing an unlicensed package")
    index = package / "upstream-licenses" / "INDEX.txt"
    index.parent.mkdir(parents=True, exist_ok=True)
    index.write_text("\n".join(sorted(collected)) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
