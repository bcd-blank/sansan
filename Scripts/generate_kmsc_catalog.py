#!/usr/bin/env python3
"""Build `Shared/Resources/kmsc_catalog.json` from the KMSC GPX tree.

The app ships the catalog only. GPX files are downloaded on demand from
`SANSANKMSCCourseBaseURL` + relativePath.

Usage:
  python3 Scripts/generate_kmsc_catalog.py
  python3 Scripts/generate_kmsc_catalog.py --export-nfc /tmp/KMSC-host
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KMSC_ROOT = ROOT / "Shared" / "Resources" / "KMSC"
CATALOG_PATH = ROOT / "Shared" / "Resources" / "kmsc_catalog.json"
ZERO_PAD_SUFFIX = re.compile(r"\s0+(\d+)$")


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def display_title(file_name: str, group_name: str) -> str:
    name = file_name.replace("_", " ").strip()
    name = ZERO_PAD_SUFFIX.sub(r" \1", name).strip()
    if not name:
        return group_name
    rest = name[len(group_name) + 1 :] if name.startswith(group_name + " ") else None
    if name == group_name or (rest is not None and rest.isdigit()):
        suffix = name[len(group_name) :].strip()
        if not suffix:
            return group_name
        return f"{group_name} {suffix}"
    return name


def collect_courses() -> list[dict[str, str]]:
    courses: list[dict[str, str]] = []
    for dirpath, dirnames, filenames in os.walk(KMSC_ROOT):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for filename in filenames:
            if filename.startswith(".") or not filename.lower().endswith(".gpx"):
                continue
            full = Path(dirpath) / filename
            relative = nfc(str(full.relative_to(KMSC_ROOT)).replace(os.sep, "/"))
            parts = relative.split("/")
            if len(parts) < 3:
                continue
            category, group_name = parts[0], parts[1]
            stem = Path(parts[-1]).stem
            courses.append(
                {
                    "id": relative,
                    "category": category,
                    "groupName": group_name,
                    "title": display_title(stem, group_name),
                    "relativePath": relative,
                }
            )
    courses.sort(key=lambda item: (item["category"], item["groupName"], item["title"]))
    return courses


def export_nfc_tree(destination: Path, courses: list[dict[str, str]]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for course in courses:
        relative = Path(course["relativePath"])
        nfd_relative = unicodedata.normalize("NFD", course["relativePath"])
        source = KMSC_ROOT / nfd_relative
        if not source.is_file():
            source = KMSC_ROOT / relative
        if not source.is_file():
            raise FileNotFoundError(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--export-nfc",
        type=Path,
        help="Copy GPX files to an NFC-normalized folder for HTTPS hosting.",
    )
    args = parser.parse_args()

    if not KMSC_ROOT.is_dir():
        raise SystemExit(f"KMSC folder not found: {KMSC_ROOT}")

    courses = collect_courses()
    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {"version": 1, "courses": courses}
    CATALOG_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(courses)} courses to {CATALOG_PATH}")

    if args.export_nfc is not None:
        export_nfc_tree(args.export_nfc, courses)
        print(f"Exported NFC GPX tree to {args.export_nfc}")


if __name__ == "__main__":
    main()
