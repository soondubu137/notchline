#!/usr/bin/env python3
"""The parts of scripts/release/cut-release.sh that are easier to get right in Python.

    release_helpers.py newer <version> <than>
    release_helpers.py label --changelog P --version V
    release_helpers.py changelog-prepare --changelog P --version V --label L --date D
    release_helpers.py release-notes --changelog P --version V --build B --tag T --repository URL
    release_helpers.py feed-item --feed P --build B
    release_helpers.py test-summary --summary P
"""

import argparse
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ElementTree

from add_feed_item import SPARKLE, changelog_section


def fail(message: str) -> None:
    sys.exit(f"error: {message}")


def version_tuple(version: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail(f"{version!r} is not major.minor.patch")
    return tuple(int(part) for part in version.split("."))


def newer(arguments: argparse.Namespace) -> None:
    sys.exit(0 if version_tuple(arguments.version) > version_tuple(arguments.than) else 1)


def label(arguments: argparse.Namespace) -> None:
    print(changelog_section(arguments.changelog, arguments.version)[0])


def changelog_prepare(arguments: argparse.Namespace) -> None:
    """Names the section `## <label> — <date>` and checks it has the house shape.

    The section is written by hand, under `## Unreleased` or already under its final heading. This
    only renames the first and refuses a section a release should not ship with.
    """
    path = arguments.changelog
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    headings = [index for index, line in enumerate(lines) if line.startswith("## ")]
    if not headings:
        fail(f"{path.name} has no sections")

    versioned = re.compile(r"^## (" + re.escape(arguments.version) + r"(?: [^—]*?)?) — ")
    found = next((index for index in headings if versioned.match(lines[index])), None)
    if found is not None:
        label = versioned.match(lines[found]).group(1).strip()
        if label != arguments.label:
            fail(f"{path.name} heads this version `{label}`, but the release is `{arguments.label}`; "
                 "fix the heading or pass the matching --stage")
    else:
        found = next((index for index in headings if lines[index].strip() == "## Unreleased"), None)
        if found is None:
            fail(f"{path.name} has no section for {arguments.version}. Write it under `## Unreleased` "
                 f"or `## {arguments.label} — {arguments.date}` first")
        lines[found] = f"## {arguments.label} — {arguments.date}\n"

    if found != headings[0]:
        fail(f"the {arguments.version} section is not the first in {path.name}; newest goes first")
    end = next((index for index in headings if index > found), len(lines))
    body = "".join(lines[found + 1 : end]).strip()
    if not body:
        fail(f"the {arguments.version} section is empty")
    if not body.startswith("**"):
        fail(f"the {arguments.version} section does not open with a bold lead paragraph")
    if not re.search(r"^Everything (else )?listed under ", body, re.M):
        fail(f"the {arguments.version} section has no `Everything listed under …` line")
    if "## Unreleased" in "".join(lines[found:end]):
        fail("an `## Unreleased` heading is left inside the section")

    path.write_text("".join(lines), encoding="utf-8")
    print(arguments.label)


def release_notes(arguments: argparse.Namespace) -> None:
    """The GitHub release body: the changelog section, the version as the app draws it after the
    lead paragraph, and relative links pinned to the tag."""
    label, body = changelog_section(arguments.changelog, arguments.version)
    lead, _, rest = body.partition("\n\n")
    notes = f"{lead}\n\nDrawn in the app as `Version {label} ({arguments.build})`.\n\n{rest}".rstrip()
    notes = re.sub(
        r"\]\((?!https?:|#|mailto:)([^)\s]+)\)",
        lambda match: f"]({arguments.repository}/blob/{arguments.tag}/{match.group(1)})",
        notes,
    )
    print(notes)


def feed_item(arguments: argparse.Namespace) -> None:
    """Prints `url length signature` for the item with this build, or exits 1 when there is none."""
    root = ElementTree.parse(arguments.feed).getroot()
    for item in root.iter("item"):
        if item.findtext(f"{{{SPARKLE}}}version") == arguments.build:
            enclosure = item.find("enclosure")
            if enclosure is None:
                fail(f"build {arguments.build} has no enclosure")
            print(enclosure.get("url"), enclosure.get("length"),
                  enclosure.get(f"{{{SPARKLE}}}edSignature"))
            return
    sys.exit(1)


def test_summary(arguments: argparse.Namespace) -> None:
    summary = json.loads(arguments.summary.read_text(encoding="utf-8"))
    passed, failed = summary.get("passedTests", 0), summary.get("failedTests", 0)
    print(f"{summary.get('result')}: {passed} passed, {failed} failed")
    if summary.get("result") != "Passed" or failed or not passed:
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    command = commands.add_parser("newer")
    command.add_argument("version")
    command.add_argument("than")
    command.set_defaults(run=newer)

    command = commands.add_parser("label")
    command.add_argument("--changelog", required=True, type=pathlib.Path)
    command.add_argument("--version", required=True)
    command.set_defaults(run=label)

    command = commands.add_parser("changelog-prepare")
    command.add_argument("--changelog", required=True, type=pathlib.Path)
    command.add_argument("--version", required=True)
    command.add_argument("--label", required=True)
    command.add_argument("--date", required=True)
    command.set_defaults(run=changelog_prepare)

    command = commands.add_parser("release-notes")
    command.add_argument("--changelog", required=True, type=pathlib.Path)
    command.add_argument("--version", required=True)
    command.add_argument("--build", required=True)
    command.add_argument("--tag", required=True)
    command.add_argument("--repository", required=True)
    command.set_defaults(run=release_notes)

    command = commands.add_parser("feed-item")
    command.add_argument("--feed", required=True, type=pathlib.Path)
    command.add_argument("--build", required=True)
    command.set_defaults(run=feed_item)

    command = commands.add_parser("test-summary")
    command.add_argument("--summary", required=True, type=pathlib.Path)
    command.set_defaults(run=test_summary)

    arguments = parser.parse_args()
    arguments.run(arguments)


if __name__ == "__main__":
    main()
