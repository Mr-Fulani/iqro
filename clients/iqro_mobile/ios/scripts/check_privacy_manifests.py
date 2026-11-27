#!/usr/bin/env python3
"""Checks a built Runner.app for "required reason" APIs that no privacy manifest explains.

    python3 ios/scripts/check_privacy_manifests.py build/ios/iphoneos/Runner.app

Apple refuses an upload (ITMS-91053) when code in the app uses an API from one of the
categories below and no privacy manifest names a reason for that category
(developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
App Store Connect looks at the binaries, so this script does too: for every Mach-O file in
the app (the app itself, each framework, the widget) it lists the imported symbols and the
Objective-C selectors, maps them to categories, and finds the manifests that cover that
binary: the ones inside its own bundle and the app's own manifest (and, for code linked into
the app, the resource bundles at the app's top level).

It fails when a category is used and no manifest declares it, or when a manifest names a
reason that does not belong to its category. A category covered only by the app's manifest,
not by the framework's own, is printed as a note: Apple's documentation asks for the
framework's own manifest, but App Store Connect has so far accepted the app's. The first
upload settles it.
"""

from __future__ import annotations

import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

FILE_TIMESTAMP = "NSPrivacyAccessedAPICategoryFileTimestamp"
SYSTEM_BOOT_TIME = "NSPrivacyAccessedAPICategorySystemBootTime"
DISK_SPACE = "NSPrivacyAccessedAPICategoryDiskSpace"
ACTIVE_KEYBOARDS = "NSPrivacyAccessedAPICategoryActiveKeyboards"
USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"

# Apple's approved reasons for each category.
REASONS = {
    FILE_TIMESTAMP: {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    SYSTEM_BOOT_TIME: {"35F9.1", "8FFB.1", "3D61.1"},
    DISK_SPACE: {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    ACTIVE_KEYBOARDS: {"3EC4.1", "54BD.1"},
    USER_DEFAULTS: {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}

# Imported C functions and Foundation constants, by exact symbol name.
SYMBOLS = {
    "_stat": {FILE_TIMESTAMP},
    "_fstat": {FILE_TIMESTAMP},
    "_fstatat": {FILE_TIMESTAMP},
    "_lstat": {FILE_TIMESTAMP},
    "_getattrlistbulk": {FILE_TIMESTAMP},
    # getattrlist reads timestamps or volume capacity, depending on what is asked:
    # either category explains it.
    "_getattrlist": {FILE_TIMESTAMP, DISK_SPACE},
    "_fgetattrlist": {FILE_TIMESTAMP, DISK_SPACE},
    "_getattrlistat": {FILE_TIMESTAMP, DISK_SPACE},
    "_NSFileCreationDate": {FILE_TIMESTAMP},
    "_NSFileModificationDate": {FILE_TIMESTAMP},
    "_NSURLContentModificationDateKey": {FILE_TIMESTAMP},
    "_NSURLCreationDateKey": {FILE_TIMESTAMP},
    "_mach_absolute_time": {SYSTEM_BOOT_TIME},
    "_statfs": {DISK_SPACE},
    "_statvfs": {DISK_SPACE},
    "_fstatfs": {DISK_SPACE},
    "_fstatvfs": {DISK_SPACE},
    "_NSFileSystemFreeSize": {DISK_SPACE},
    "_NSFileSystemSize": {DISK_SPACE},
    "_NSURLVolumeAvailableCapacityKey": {DISK_SPACE},
    "_NSURLVolumeAvailableCapacityForImportantUsageKey": {DISK_SPACE},
    "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey": {DISK_SPACE},
    "_NSURLVolumeTotalCapacityKey": {DISK_SPACE},
    "_OBJC_CLASS_$_NSUserDefaults": {USER_DEFAULTS},
}

# Swift Foundation accessors, by mangled name: the URLResourceValues properties, and
# Foundation's Swift methods on NSUserDefaults (the class itself is caught above).
SWIFT_PATTERNS = [
    (re.compile(r"^_\$s10Foundation17URLResourceValuesV.*(creationDate|contentModificationDate)"), {FILE_TIMESTAMP}),
    (re.compile(r"^_\$s10Foundation17URLResourceValuesV.*volume(AvailableCapacity|TotalCapacity)"), {DISK_SPACE}),
    (re.compile(r"^_\$sSo14NSUserDefaultsC10Foundation"), {USER_DEFAULTS}),
]

# Objective-C (and Swift calling Objective-C) methods, by selector.
SELECTORS = {
    "systemUptime": {SYSTEM_BOOT_TIME},
    "activeInputModes": {ACTIVE_KEYBOARDS},
    "fileModificationDate": {FILE_TIMESTAMP},
}


def tool(name: str) -> str:
    if shutil.which("xcrun"):
        found = subprocess.run(["xcrun", "--find", name], capture_output=True, text=True)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    path = shutil.which(name)
    if not path:
        sys.exit(f"error: {name} not found")
    return path


NM = tool("nm")
OTOOL = tool("otool")


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in {
        b"\xcf\xfa\xed\xfe",  # 64-bit
        b"\xce\xfa\xed\xfe",  # 32-bit
        b"\xca\xfe\xba\xbe",  # universal
        b"\xbe\xba\xfe\xca",
    }


def imported_symbols(binary: Path) -> set[str]:
    result = subprocess.run([NM, "-u", "-j", str(binary)], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"error: nm failed on {binary}: {result.stderr.strip()}")
    return {line.strip() for line in result.stdout.splitlines() if line.strip() and not line.endswith(":")}


def selectors(binary: Path) -> set[str]:
    result = subprocess.run(
        [OTOOL, "-v", "-s", "__TEXT", "__objc_methname", str(binary)], capture_output=True, text=True
    )
    names = set()
    for line in result.stdout.splitlines():
        # "0000000100004000  systemUptime" — the address, then the C string.
        parts = line.split(None, 1)
        if len(parts) == 2 and re.fullmatch(r"[0-9a-fA-F]+", parts[0]):
            names.add(parts[1].strip())
    return names


def used_categories(binary: Path) -> dict[frozenset[str], set[str]]:
    """Each needed choice of categories (any one explains it) with the APIs behind it."""
    needs: dict[frozenset[str], set[str]] = {}
    for symbol in imported_symbols(binary):
        bare = symbol.split("$INODE64")[0]
        categories = SYMBOLS.get(bare)
        if categories is None:
            for pattern, found in SWIFT_PATTERNS:
                if pattern.search(symbol):
                    categories = found
                    break
        if categories:
            needs.setdefault(frozenset(categories), set()).add(bare)
    for name in selectors(binary):
        categories = SELECTORS.get(name)
        if categories:
            needs.setdefault(frozenset(categories), set()).add(name)
    return needs


@dataclass
class Manifest:
    path: Path
    declared: dict[str, set[str]] = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)


def read_manifest(path: Path) -> Manifest:
    manifest = Manifest(path)
    try:
        data = plistlib.loads(path.read_bytes())
    except Exception as error:  # noqa: BLE001 - any unreadable manifest is a failure
        manifest.problems.append(f"cannot be read: {error}")
        return manifest
    for entry in data.get("NSPrivacyAccessedAPITypes", []) or []:
        category = entry.get("NSPrivacyAccessedAPIType", "")
        reasons = set(entry.get("NSPrivacyAccessedAPITypeReasons", []) or [])
        if category not in REASONS:
            manifest.problems.append(f"unknown category {category!r}")
            continue
        if not reasons:
            manifest.problems.append(f"{category} has no reason")
        wrong = reasons - REASONS[category]
        if wrong:
            manifest.problems.append(f"{category}: reasons {sorted(wrong)} do not belong to it")
        manifest.declared.setdefault(category, set()).update(reasons & REASONS[category])
    return manifest


def owner(path: Path, app: Path) -> Path:
    """The innermost .framework or .appex holding the path, else the app itself."""
    for parent in path.parents:
        if parent == app:
            break
        if parent.suffix in {".framework", ".appex"}:
            return parent
    return app


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    app = Path(sys.argv[1]).resolve()
    if not (app / "Info.plist").is_file():
        sys.exit(f"error: {app} is not an app bundle")

    manifests = [read_manifest(path) for path in sorted(app.rglob("PrivacyInfo.xcprivacy"))]
    app_manifest = app / "PrivacyInfo.xcprivacy"
    failures: list[str] = []
    notes: list[str] = []
    for manifest in manifests:
        for problem in manifest.problems:
            failures.append(f"{manifest.path.relative_to(app)}: {problem}")
    if not app_manifest.is_file():
        failures.append("the app has no PrivacyInfo.xcprivacy")

    binaries = sorted(
        path for path in app.rglob("*") if path.is_file() and not path.is_symlink() and is_macho(path)
    )
    if not binaries:
        sys.exit(f"error: no binaries found in {app}")

    print(f"Required-reason APIs in {app.name}")
    for binary in binaries:
        bundle = owner(binary, app)
        own = [m for m in manifests if owner(m.path, app) == bundle]
        # Code linked into the app is covered by the app's manifest and the resource
        # bundles copied next to it; a framework or widget by its own and the app's.
        covering = own if bundle == app else own + [m for m in manifests if m.path == app_manifest]
        needs = used_categories(binary)
        label = binary.relative_to(app)
        if not needs:
            print(f"  {label}: none")
            continue
        for choice, apis in sorted(needs.items(), key=lambda item: sorted(item[0])):
            names = " or ".join(sorted(c.removeprefix("NSPrivacyAccessedAPICategory") for c in choice))
            where = [m for m in covering if choice & m.declared.keys()]
            shown = ", ".join(sorted(apis))
            if not where:
                print(f"  {label}: {names} ({shown}) — NOT DECLARED")
                failures.append(f"{label} uses {names} ({shown}) and no manifest gives a reason")
                continue
            places = ", ".join(str(m.path.relative_to(app)) for m in where)
            print(f"  {label}: {names} ({shown}) — declared in {places}")
            if bundle != app and not any(m in own for m in where):
                notes.append(f"{label}: {names} is declared only in the app's manifest")

    if notes:
        print("\nNotes:")
        for note in notes:
            print(f"  {note}")
    if failures:
        print("\nFailed:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("\nEvery required-reason API is declared.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
