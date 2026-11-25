#!/usr/bin/env python3
"""Prints the next release version for HEAD from its Conventional Commits, or nothing if HEAD needs no release.

The bump is measured from the last release HEAD contains (vX.Y.Z), over every commit since then:
  breaking change (type!: or a BREAKING CHANGE: footer)  major, or minor while still at 0.x
  feat                                                   minor
  fix, perf                                              patch
  anything else (ci, docs, chore, style, test, ...)      no release
"""
import re
import subprocess
import sys

RELEASE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
TYPE = re.compile(r"^(\w+)(\([^)]*\))?(!)?:")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def bump_level(rev_range):
    """0 none, 1 patch, 2 minor, 3 major, for the commits in rev_range."""
    level = 0
    for commit in git("log", "--format=%s%n%b%x1e", rev_range).split("\x1e"):
        commit = commit.strip()
        if not commit:
            continue
        m = TYPE.match(commit)
        kind = m.group(1).lower() if m else ""
        if (m and m.group(3)) or re.search(r"^BREAKING[ -]CHANGE:", commit, re.M):
            level = max(level, 3)
        elif kind == "feat":
            level = max(level, 2)
        elif kind in ("fix", "perf"):
            level = max(level, 1)
    return level


def main():
    releases = [tuple(map(int, m.groups())) for t in git("tag", "--list", "v*", "--merged", "HEAD").split()
                if (m := RELEASE.match(t))]
    base = max(releases, default=None)
    level = bump_level(f"v{base[0]}.{base[1]}.{base[2]}..HEAD" if base else "HEAD")
    if level == 0:
        return

    major, minor, patch = base or (0, 0, 0)
    if level == 3 and major > 0:
        target = (major + 1, 0, 0)
    elif level >= 2:
        target = (major, minor + 1, 0)
    else:
        target = (major, minor, patch + 1)
    print("%d.%d.%d" % target)


if __name__ == "__main__":
    sys.exit(main())
