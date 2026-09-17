#!/usr/bin/env python3
"""Checks that every relative link in the repository's tracked Markdown resolves on GitHub.

    scripts/check-doc-links.py        one line per broken link; exits 1 if there is any

A link resolves when its path names a tracked file, or a directory holding one, and, for a Markdown
target, its fragment names a heading or an HTML anchor there. Only tracked files count: a file that
exists on this Mac but not in git is a 404 on GitHub. Inline links, images, reference definitions
and HTML `href`/`src` are read; code and comments are not. External links are never fetched.
"""

import collections
import os
import posixpath
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                      check=True).stdout.strip()

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
# A span closes on a backtick run of its own length and never crosses a blank line, so a stray
# backtick hides nothing after its paragraph.
CODE_SPAN = re.compile(r"(?<!`)(`+)(?!`)((?:(?!\n[ \t]*\n).)+?)(?<!`)\1(?!`)", re.S)
COMMENT = re.compile(r"<!--.*?-->", re.S)
# Link text may hold one level of brackets and may wrap onto the next line.
INLINE = re.compile(r"!?\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*(<[^>\n]*>|[^\s)]+)"
                    r"(?:\s+(?:\"[^\"]*\"|'[^']*'|\([^)]*\)))?\s*\)")
REFERENCE = re.compile(r"^ {0,3}\[[^\]\n]+\]:[ \t]*(<[^>\n]*>|\S+)", re.M)
HTML = re.compile(r"\b(?:href|src)\s*=\s*\"([^\"]*)\"")
HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
HTML_ANCHOR = re.compile(r"<a\s[^>]*?\b(?:id|name)\s*=\s*\"([^\"]+)\"")
SCHEME = re.compile(r"^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)")


def blank(match: re.Match) -> str:
    """Keeps a removed span's newlines, so offsets still give the right line."""
    return re.sub(r"[^\n]", " ", match.group(0))


def without_fences(text: str) -> str:
    lines = text.split("\n")
    opener = None
    for index, line in enumerate(lines):
        fence = FENCE.match(line)
        if opener is None:
            if fence:
                opener = fence.group(1)
                lines[index] = ""
        else:
            if fence and fence.group(1)[0] == opener[0] and len(fence.group(1)) >= len(opener) \
                    and not line[fence.end():].strip():
                opener = None
            lines[index] = ""
    return "\n".join(lines)


def slug(heading: str) -> str:
    """GitHub's anchor for a heading: the rendered text, lower-cased, keeping letters, marks,
    numbers, connector punctuation, hyphens and spaces, with each space made a hyphen."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = CODE_SPAN.sub(r"\2", text)
    text = re.sub(r"<[^>]+>", "", text)
    # Emphasis delimiters are not rendered; an underscore inside a word is.
    text = re.sub(r"\*+|(?<!\w)_+|_+(?!\w)", "", text)
    kept = (character for character in text.strip().lower()
            if character in " -" or unicodedata.category(character)[0] in "LMN"
            or unicodedata.category(character) == "Pc")
    return "".join(kept).replace(" ", "-")


def anchors(path: str, cache: dict) -> set:
    if path not in cache:
        found, used = set(), collections.Counter()
        with open(os.path.join(ROOT, path), encoding="utf-8") as file:
            text = file.read()
        for line in without_fences(text).split("\n"):
            heading = HEADING.match(line)
            if heading:
                base = candidate = slug(heading.group(1))
                while candidate in found:
                    used[base] += 1
                    candidate = f"{base}-{used[base]}"
                found.add(candidate)
            found.update(anchor.lower() for anchor in HTML_ANCHOR.findall(line))
        cache[path] = found
    return cache[path]


def problem(source: str, target: str, tracked: set, directories: set, cache: dict):
    """Why this link does not resolve, or None."""
    path, _, fragment = target.partition("#")
    path, fragment = unquote(path), unquote(fragment)
    if not path:
        resolved = source
    else:
        base = "" if path.startswith("/") else posixpath.dirname(source)
        resolved = posixpath.normpath(posixpath.join(base, path.lstrip("/"))).rstrip("/")
        if resolved == ".." or resolved.startswith("../"):
            return "leaves the repository"
        if resolved != "." and resolved not in tracked and resolved not in directories:
            if os.path.exists(os.path.join(ROOT, resolved)):
                return "exists here but is not tracked, so GitHub has no such file"
            return "no such file"
    if fragment and resolved.lower().endswith(".md") and resolved in tracked:
        if fragment.lower() not in anchors(resolved, cache):
            return f"no heading or anchor #{fragment} in {resolved}"
    return None


def main() -> int:
    listed = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, text=True,
                            check=True).stdout
    tracked = set(filter(None, listed.split("\0")))
    directories = {posixpath.dirname(path) for path in tracked}
    for directory in list(directories):
        while directory:
            directories.add(directory)
            directory = posixpath.dirname(directory)

    cache, broken, checked = {}, [], 0
    for source in sorted(path for path in tracked if path.lower().endswith(".md")):
        with open(os.path.join(ROOT, source), encoding="utf-8") as file:
            text = without_fences(file.read())
        text = COMMENT.sub(blank, CODE_SPAN.sub(blank, text))
        found = [(match.start(), match.group(1)) for pattern in (INLINE, REFERENCE, HTML)
                 for match in pattern.finditer(text)]
        for offset, raw in sorted(found):
            target = raw[1:-1].strip() if raw.startswith("<") and raw.endswith(">") else raw
            if not target or SCHEME.match(target):
                continue
            checked += 1
            reason = problem(source, target, tracked, directories, cache)
            if reason:
                broken.append((source, text.count("\n", 0, offset) + 1, f"{target} — {reason}"))

    # Under GitHub Actions, the same lines as annotations on the pull request's diff.
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    for source, line, message in broken:
        print(f"::error file={source},line={line}::{message}" if annotate else f"{source}:{line}: {message}")
    print(f"{checked} relative links checked, {len(broken)} broken.", file=sys.stderr)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
