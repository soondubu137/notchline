#!/usr/bin/env python3
"""Adds one release to the Sparkle feed, newest first.

The item's title and notes come from the version's section of CHANGELOG.md, so the feed says what
the GitHub release says. The notes are embedded as Markdown, which Sparkle renders in its update
alert; the full release page is linked beside them.
"""

import argparse
import email.utils
import pathlib
import re
import sys
import xml.etree.ElementTree as ElementTree

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def changelog_section(changelog: pathlib.Path, version: str) -> tuple[str, str]:
    """Returns the heading's label (`0.4.3 Alpha`) and the section body."""
    lines = changelog.read_text(encoding="utf-8").splitlines()
    heading = re.compile(r"^## (" + re.escape(version) + r"(?: [^—]*?)?) — ")
    for start, line in enumerate(lines):
        match = heading.match(line)
        if match:
            break
    else:
        sys.exit(f"error: CHANGELOG.md has no section for {version}; cut the version first")
    end = next(
        (index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")),
        len(lines),
    )
    return match.group(1).strip(), "\n".join(lines[start + 1 : end]).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed", required=True, type=pathlib.Path)
    parser.add_argument("--changelog", required=True, type=pathlib.Path)
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString")
    parser.add_argument("--build", required=True, help="CFBundleVersion")
    parser.add_argument("--minimum-system-version", required=True)
    parser.add_argument("--archive-url", required=True)
    parser.add_argument("--release-url", required=True)
    parser.add_argument("--signature-attributes", required=True,
                        help='sign_update output: sparkle:edSignature="…" length="…"')
    arguments = parser.parse_args()

    if not re.fullmatch(r'sparkle:edSignature="[A-Za-z0-9+/=]+" length="\d+"',
                        arguments.signature_attributes.strip()):
        sys.exit(f"error: unexpected sign_update output: {arguments.signature_attributes!r}")

    feed = arguments.feed.read_text(encoding="utf-8")
    existing = ElementTree.fromstring(feed)
    for version in existing.iter(f"{{{SPARKLE}}}version"):
        if version.text == arguments.build:
            sys.exit(f"error: the feed already has build {arguments.build}")
        if int(version.text) > int(arguments.build):
            sys.exit(f"error: the feed already has a later build, {version.text}")

    label, notes = changelog_section(arguments.changelog, arguments.version)
    if "]]>" in notes:
        sys.exit("error: the changelog section contains ]]>, which cannot sit inside CDATA")

    item = f"""    <item>
      <title>Notchline {label}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{arguments.build}</sparkle:version>
      <sparkle:shortVersionString>{arguments.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{arguments.minimum_system_version}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{arguments.release_url}</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[{notes}
]]></description>
      <enclosure url="{arguments.archive_url}" type="application/octet-stream" {arguments.signature_attributes.strip()}/>
    </item>
"""

    anchor = feed.find("    <item>")
    if anchor < 0:
        anchor = feed.find("  </channel>")
    if anchor < 0:
        sys.exit(f"error: {arguments.feed} has no <channel>")
    updated = feed[:anchor] + item + feed[anchor:]
    ElementTree.fromstring(updated)  # still well-formed
    arguments.feed.write_text(updated, encoding="utf-8")
    print(f"added Notchline {label} ({arguments.build}) to {arguments.feed}")


if __name__ == "__main__":
    main()
