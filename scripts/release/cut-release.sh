#!/bin/bash
# Cuts, builds and publishes one Notchline version, end to end.
#
#   scripts/release/cut-release.sh <version> [--stage <word> | --stage none] [--local] [--skip-tests]
#                                  [--keep-build] [--yes]
#
# Write the version's CHANGELOG.md section first, under `## Unreleased` or under its final heading
# `## <version> <Stage> — <date>`. It needs a bold lead paragraph and an `Everything listed under …`
# line. The script writes no prose. It does the rest, in order:
#
#   1. Cut      bump the six version settings and the build number, both README badges and, with
#               --stage, the stage word; name the changelog section; run the unit suite; commit
#               "Cut <version> <Stage>" and tag v<version>. Local only.
#   2. Push     master and the tag.                                                     (asks)
#   3. Release  a GitHub pre-release, not Latest, whose notes are the changelog section.   (asks)
#   4. Build    scripts/release/build-release.sh on the tag, then check the archive's version,
#               length and EdDSA signature against the public key.
#   5. Upload   the archive, then check GitHub's digest against the local file.            (asks)
#   6. Feed     commit appcast.xml and push it, only after the upload.                  (asks)
#   7. Verify   signed out: wait for raw.githubusercontent.com's cache to serve the new feed, then
#               download the archive from the feed's link and check its size and signature.
#   8. Clean    delete what this version left under build/release: the app, archive, logs, test
#               results and DerivedData. Only after step 7; a failed run keeps all of it.
#
# Every step first checks whether it has already happened, so a run that stopped part-way resumes
# when the same command is run again. Nothing leaves this Mac without a yes.
#
#   --stage <word>  change the stage word (`Beta`, `RC`); `none` drops it. Default: keep it.
#   --local         stop after step 1, to read the cut commit before anything is published.
#   --skip-tests    do not run the unit suite in step 1.
#   --keep-build    skip step 8 and leave the build where it is.
#   --yes           answer yes to every question; needed when stdin is not a terminal.

source "$(dirname "$0")/common.sh"

HELPERS="$REPO_ROOT/scripts/release/release_helpers.py"
APP_VERSION_FILE="$REPO_ROOT/Notchline/Notchline/AppVersion.swift"
PBXPROJ_PATH=Notchline/Notchline.xcodeproj/project.pbxproj
REPOSITORY_SLUG=${REPOSITORY_URL#https://github.com/}
POLL_SECONDS=20
POLL_LIMIT=30
# The helpers import add_feed_item; a __pycache__ beside them would dirty the tree a cut checks.
export PYTHONDONTWRITEBYTECODE=1

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

version=
stage_argument=
local_only=false
skip_tests=false
keep_build=false
assume_yes=false
while [ $# -gt 0 ]; do
    case $1 in
        --stage) [ $# -ge 2 ] || die "--stage needs a word, or none"; stage_argument=$2; shift ;;
        --local) local_only=true ;;
        --skip-tests) skip_tests=true ;;
        --keep-build) keep_build=true ;;
        --yes) assume_yes=true ;;
        -h | --help) usage; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) [ -z "$version" ] || die "one version at a time"; version=$1 ;;
    esac
    shift
done
[ -n "$version" ] || { usage; exit 1; }
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$version is not major.minor.patch"

tag="v$version"
archive_name="Notchline-$version.zip"
archive="$BUILD_ROOT/$version/$archive_name"
scratch=$(mktemp -d -t notchline-cut)
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

confirm() {
    if $assume_yes; then
        echo "    yes (--yes): $1"
        return 0
    fi
    [ -t 0 ] || die "\"$1\" needs a yes: run this in a terminal, or pass --yes"
    local answer
    read -r -p "    $1 [y/N] " answer
    case $answer in
        y | Y | yes) ;;
        *) die "stopped before: $1 Run the same command again to resume from here." ;;
    esac
}

# The one value a build setting has across every configuration, from the working tree or a revision.
build_setting() {
    local name=$1 revision=${2:-} content values
    if [ -n "$revision" ]; then
        content=$(git -C "$REPO_ROOT" show "$revision:$PBXPROJ_PATH")
    else
        content=$(cat "$PBXPROJ")
    fi
    values=$(printf '%s\n' "$content" | sed -n "s/^[[:space:]]*$name = \(.*\);\$/\1/p" | tr -d '"' | sort -u)
    [ -n "$values" ] || die "project.pbxproj has no $name"
    [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" -eq 1 ] \
        || die "$name has more than one value in project.pbxproj: $(echo $values)"
    printf '%s' "$values"
}

setting_count() {
    grep -c "^[[:space:]]*$1 = " "$PBXPROJ" || true
}

current_stage() {
    local value
    value=$(sed -n 's/^[[:space:]]*static let stage: String? = \(.*\)$/\1/p' "$APP_VERSION_FILE")
    case $value in
        nil) echo none ;;
        \"*\") value=${value#\"}; echo "${value%\"}" ;;
        *) die "cannot read the stage word in $APP_VERSION_FILE" ;;
    esac
}

label_for() {
    if [ "$1" = none ]; then echo "$version"; else echo "$version $1"; fi
}

# `url length signature` for this build's feed item, read from a file; empty when there is none.
feed_item() {
    python3 "$HELPERS" feed-item --feed "$1" --build "$build" || true
}

feed_has_build() {
    [ -n "$(feed_item "$1")" ]
}

asset_field() {
    gh release view "$tag" --repo "$REPOSITORY_SLUG" --json assets \
        --jq ".assets[] | select(.name == \"$archive_name\") | .$1" 2>/dev/null || true
}

verify_signature() {
    swift "$REPO_ROOT/scripts/release/verify_signature.swift" "$public_key" "$1" "$2" \
        || die "the archive's EdDSA signature does not verify against SUPublicEDKey"
}

# ---------------------------------------------------------------------------------------------
cd "$REPO_ROOT"
step "Checking the checkout"
command -v gh >/dev/null || die "the GitHub CLI (gh) is needed"
gh auth status >/dev/null 2>&1 || die "gh is not signed in (gh auth login)"
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = master ] || die "a release is cut on master"
git fetch --quiet --tags origin
[ -z "$(git rev-list HEAD..origin/master)" ] || die "master is behind origin/master; pull first"
[ -n "$(certificate_sha1)" ] || die "no certificate named \"$IDENTITY_NAME\" in $KEYCHAIN"
public_key=$(build_setting NOTCHLINE_UPDATE_PUBLIC_ED_KEY)
feed_url=$(build_setting NOTCHLINE_UPDATE_FEED_URL)
dirty=$(git status --porcelain)

# --- 1. Cut ----------------------------------------------------------------------------------
undo_cut_edits() {
    git checkout --quiet -- "$PBXPROJ_PATH" README.md README.zh-CN.md Notchline/Notchline/AppVersion.swift
    echo "    The version edits were undone; CHANGELOG.md is left as it is." >&2
    cleanup
}

apply_version_edits() {
    sed -i '' \
        -e "s/^\([[:space:]]*MARKETING_VERSION = \)${current_version//./\\.};\$/\1$version;/" \
        -e "s/^\([[:space:]]*CURRENT_PROJECT_VERSION = \)$current_build;\$/\1$build;/" \
        "$PBXPROJ"
}

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    cut_commit=$(git rev-parse "$tag^{commit}")
    git merge-base --is-ancestor "$cut_commit" HEAD || die "$tag is not on master"
    [ "$(build_setting MARKETING_VERSION "$tag")" = "$version" ] || die "$tag does not carry MARKETING_VERSION $version"
    build=$(build_setting CURRENT_PROJECT_VERSION "$tag")
    git show "$tag:CHANGELOG.md" > "$scratch/CHANGELOG.md"
    label=$(python3 "$HELPERS" label --changelog "$scratch/CHANGELOG.md" --version "$version")
    step "1. Cut: already done ($tag, $label, build $build)"
    case $dirty in
        "") ;;
        " M appcast.xml") ;;
        *) die "the working tree has changes other than appcast.xml:
$dirty" ;;
    esac
else
    step "1. Cut $version"
    others=$(printf '%s\n' "$dirty" | grep -v -E '^(.M|M.) CHANGELOG\.md$' | grep . || true)
    [ -z "$others" ] || die "only CHANGELOG.md may have changes before a cut:
$others"
    [ "$(setting_count MARKETING_VERSION)" -eq 6 ] || die "expected six MARKETING_VERSION settings"
    [ "$(setting_count CURRENT_PROJECT_VERSION)" -eq 6 ] || die "expected six CURRENT_PROJECT_VERSION settings"
    current_version=$(build_setting MARKETING_VERSION)
    current_build=$(build_setting CURRENT_PROJECT_VERSION)
    python3 "$HELPERS" newer "$version" "$current_version" \
        || die "$version is not newer than the current $current_version"
    build=$((current_build + 1))
    stage=$stage_argument
    [ -n "$stage" ] || stage=$(current_stage)
    label=$(label_for "$stage")

    python3 "$HELPERS" changelog-prepare --changelog "$CHANGELOG_FILE" --version "$version" \
        --label "$label" --date "$(date +%F)" >/dev/null
    echo "    CHANGELOG.md: ## $label"

    trap undo_cut_edits EXIT
    apply_version_edits
    [ "$(build_setting MARKETING_VERSION)" = "$version" ] || die "MARKETING_VERSION did not become $version"
    [ "$(build_setting CURRENT_PROJECT_VERSION)" = "$build" ] || die "CURRENT_PROJECT_VERSION did not become $build"
    for readme in README.md README.zh-CN.md; do
        sed -i '' "s#badge/version-[0-9.]*-blue\" alt=\"Version [0-9.]*\"#badge/version-$version-blue\" alt=\"Version $version\"#" "$readme"
        grep -q "badge/version-$version-blue\" alt=\"Version $version\"" "$readme" || die "no version badge in $readme"
    done
    if [ "$stage" != "$(current_stage)" ]; then
        if [ "$stage" = none ]; then replacement=nil; else replacement="\"$stage\""; fi
        sed -i '' "s/^\([[:space:]]*static let stage: String? = \).*\$/\1$replacement/" "$APP_VERSION_FILE"
        [ "$(current_stage)" = "$stage" ] || die "the stage word did not become $stage"
    fi
    echo "    $current_version ($current_build) → $label ($build)"

    if $skip_tests; then
        echo "    unit suite skipped (--skip-tests)"
    else
        step "   Running the unit suite"
        while pgrep -f "xcodebuild test" >/dev/null; do
            echo "    another xcodebuild test is running; waiting for it"
            sleep 20
        done
        results="$BUILD_ROOT/tests-$version.xcresult"
        rm -rf "$results"
        mkdir -p "$BUILD_ROOT"
        xcodebuild test -project "$PROJECT" -scheme Notchline -destination 'platform=macOS' \
            -only-testing:NotchlineTests -resultBundlePath "$results" > "$BUILD_ROOT/tests-$version.log" 2>&1 || true
        xcrun xcresulttool get test-results summary --path "$results" > "$scratch/summary.json" 2>/dev/null \
            || die "the unit suite produced no results; see $BUILD_ROOT/tests-$version.log"
        python3 "$HELPERS" test-summary --summary "$scratch/summary.json" \
            || die "the unit suite did not pass (a flake under load passes on a re-run); see $BUILD_ROOT/tests-$version.log"
        # A build reorders a line in project.pbxproj; keep only the version edits.
        if git diff -U0 -- "$PBXPROJ_PATH" | grep '^[-+][^-+]' | grep -v -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' >/dev/null; then
            git checkout --quiet -- "$PBXPROJ_PATH"
            apply_version_edits
        fi
    fi

    unexpected=$(git status --porcelain | grep -v -E '^ M (CHANGELOG\.md|README\.md|README\.zh-CN\.md|Notchline/Notchline\.xcodeproj/project\.pbxproj|Notchline/Notchline/AppVersion\.swift)$' || true)
    [ -z "$unexpected" ] || die "files changed that a cut does not touch:
$unexpected"
    git diff --stat
    git add CHANGELOG.md README.md README.zh-CN.md "$PBXPROJ_PATH" Notchline/Notchline/AppVersion.swift
    git commit --quiet -m "Cut $label"
    git tag -a "$tag" -m "Notchline $label"
    trap cleanup EXIT
    cut_commit=$(git rev-parse HEAD)
    echo "    committed $(git log --oneline -1) and tagged $tag"
fi

if $local_only; then
    cat <<EOF

Stopped after the cut (--local). Nothing is published. Read it with
  git show $tag
then run the same command without --local to publish. To abandon it instead:
  git tag -d $tag && git reset --hard HEAD~1
EOF
    exit 0
fi

# --- 2. Push ---------------------------------------------------------------------------------
remote_tag=$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)
if [ -n "$remote_tag" ]; then
    [ "$remote_tag" = "$cut_commit" ] || die "origin's $tag is $remote_tag, not $cut_commit"
fi
if [ -n "$remote_tag" ] && git merge-base --is-ancestor "$cut_commit" origin/master; then
    step "2. Push: already done"
else
    step "2. Push"
    git log --oneline origin/master..HEAD | sed 's/^/    /'
    confirm "Push master (the commits above) and $tag to origin?"
    git push --quiet origin master "$tag"
    git fetch --quiet origin
fi

# --- 3. GitHub release -----------------------------------------------------------------------
if gh release view "$tag" --repo "$REPOSITORY_SLUG" >/dev/null 2>&1; then
    step "3. Release: already exists"
else
    step "3. Release"
    git show "$tag:CHANGELOG.md" > "$scratch/CHANGELOG.md"
    python3 "$HELPERS" release-notes --changelog "$scratch/CHANGELOG.md" --version "$version" \
        --build "$build" --tag "$tag" --repository "$REPOSITORY_URL" > "$scratch/notes.md"
    sed 's/^/    │ /' "$scratch/notes.md"
    confirm "Create the pre-release \"Notchline $label\" with these notes?"
    gh release create "$tag" --repo "$REPOSITORY_SLUG" --verify-tag --title "Notchline $label" \
        --notes-file "$scratch/notes.md" --prerelease --latest=false >/dev/null
fi
[ "$(gh release view "$tag" --repo "$REPOSITORY_SLUG" --json isPrerelease,isDraft --jq '"\(.isPrerelease) \(.isDraft)"')" = "true false" ] \
    || die "the $tag release is not a published pre-release"
latest=$(gh api "repos/$REPOSITORY_SLUG/releases/latest" --jq .tag_name 2>/dev/null || true)
[ "$latest" != "$tag" ] || die "the $tag release is marked Latest; releases/latest must stay unused (ADR 0022)"

# --- 4. Build, 5. Upload, 6. Feed ------------------------------------------------------------
git show "origin/master:appcast.xml" > "$scratch/origin-feed.xml"
git show "HEAD:appcast.xml" > "$scratch/head-feed.xml"
if feed_has_build "$scratch/origin-feed.xml"; then
    step "4–6. Build, upload and feed: already published"
else
    if feed_has_build "$scratch/head-feed.xml"; then
        step "4–5. Build and upload: the feed commit already exists"
    else
        if feed_has_build "$FEED_FILE" && [ -f "$archive" ]; then
            step "4. Build: reusing $archive"
        else
            step "4. Build"
            [ -z "$(git status --porcelain)" ] || die "appcast.xml has changes but $archive is gone; git checkout appcast.xml and re-run"
            [ "$(git rev-parse HEAD)" = "$cut_commit" ] || die "HEAD has moved past $tag; a release is built from the tagged commit"
            mkdir -p "$BUILD_ROOT"
            build_log="$BUILD_ROOT/build-$version.log"
            "$REPO_ROOT/scripts/release/build-release.sh" > "$build_log" 2>&1 \
                || die "build-release.sh failed; the end of $build_log:
$(tail -20 "$build_log")"
            grep -E '^(==>|added|Built)' "$build_log" | sed 's/^/    /' || true
            [ -f "$archive" ] || die "build-release.sh made no $archive"
            if [ -n "$(git status --porcelain -- "$PBXPROJ_PATH")" ]; then
                git checkout --quiet -- "$PBXPROJ_PATH"
            fi
        fi
        read -r item_url item_length item_signature <<< "$(feed_item "$FEED_FILE")"
        [ -n "${item_signature:-}" ] || die "appcast.xml has no item for build $build"
        [ "$(stat -f %z "$archive")" = "$item_length" ] || die "$archive is not the feed's $item_length bytes"
        unzip -p "$archive" Notchline.app/Contents/Info.plist > "$scratch/Info.plist"
        [ "$(plutil -extract CFBundleShortVersionString raw "$scratch/Info.plist")" = "$version" ] || die "the archive is not $version"
        [ "$(plutil -extract CFBundleVersion raw "$scratch/Info.plist")" = "$build" ] || die "the archive is not build $build"
        [ "$(plutil -extract SUPublicEDKey raw "$scratch/Info.plist")" = "$public_key" ] || die "the archive carries a different SUPublicEDKey"
        echo "    $archive_name: $version ($build), $item_length bytes"
        signature_result=$(verify_signature "$item_signature" "$archive")
        echo "    $signature_result"

        step "5. Upload"
        local_digest="sha256:$(shasum -a 256 "$archive" | cut -d' ' -f1)"
        uploaded=$(asset_field digest)
        if [ -z "$uploaded" ]; then
            confirm "Upload $archive_name to the $tag release?"
            gh release upload "$tag" "$archive" --repo "$REPOSITORY_SLUG"
            uploaded=$(asset_field digest)
        else
            echo "    already uploaded"
        fi
        [ "$uploaded" = "$local_digest" ] || die "GitHub's $archive_name is $uploaded, not the local $local_digest.
    A rebuilt archive never matches an uploaded one. Delete the asset and re-run:
      gh release delete-asset $tag $archive_name --repo $REPOSITORY_SLUG"
        echo "    GitHub's copy matches ($local_digest)"

        git add appcast.xml
        git commit --quiet -m "Offer $version to the update feed"
        echo "    committed $(git log --oneline -1)"
    fi

    step "6. Feed"
    git show "HEAD:appcast.xml" > "$scratch/head-feed.xml"
    read -r item_url item_length item_signature <<< "$(feed_item "$scratch/head-feed.xml")"
    [ "$(asset_field size)" = "$item_length" ] || die "the $tag release has no $item_length-byte $archive_name; upload it before the feed"
    confirm "Push the feed? Every installed copy is offered $label from then on."
    git push --quiet origin master
    git fetch --quiet origin
fi

# --- 7. Verify, signed out -------------------------------------------------------------------
step "7. Verify, signed out"
git show "origin/master:appcast.xml" > "$scratch/origin-feed.xml"
read -r item_url item_length item_signature <<< "$(feed_item "$scratch/origin-feed.xml")"
anonymous_curl() {
    env -u GH_TOKEN -u GITHUB_TOKEN curl -q -fsSL --proto '=https' "$@"
}
attempt=1
until anonymous_curl -o "$scratch/public-feed.xml" "$feed_url" && cmp -s "$scratch/public-feed.xml" "$scratch/origin-feed.xml"; do
    [ "$attempt" -lt "$POLL_LIMIT" ] || die "$feed_url still does not serve origin/master's appcast.xml"
    echo "    the public feed is not origin/master's yet (GitHub caches it for five minutes); waiting"
    attempt=$((attempt + 1))
    sleep "$POLL_SECONDS"
done
echo "    $feed_url serves origin/master's appcast.xml"
anonymous_curl -o "$scratch/$archive_name" "$item_url" || die "cannot download $item_url signed out"
[ "$(stat -f %z "$scratch/$archive_name")" = "$item_length" ] || die "the public $archive_name is not $item_length bytes"
echo "    $item_url: $item_length bytes"
signature_result=$(verify_signature "$item_signature" "$scratch/$archive_name")
echo "    $signature_result"

# --- 8. Clean --------------------------------------------------------------------------------
# Not before step 7 passes: until then a re-run needs the archive (a rebuild never matches the
# uploaded asset) and a failure needs the logs. A published version's re-run never reads any of it.
build_note=
if $keep_build; then
    build_note="  - $BUILD_ROOT holds the build and its DerivedData (--keep-build); delete it when you like."
else
    step "8. Clean"
    removable=("$BUILD_ROOT/$version" "$BUILD_ROOT/build-$version.log"
        "$BUILD_ROOT/tests-$version.log" "$BUILD_ROOT/tests-$version.xcresult")
    # A DERIVED_DATA overridden to somewhere else may be shared; only the default one is this run's.
    if [ "$DERIVED_DATA" = "$BUILD_ROOT/DerivedData" ]; then
        removable+=("$DERIVED_DATA")
    fi
    rm -rf "${removable[@]}"
    if rmdir "$BUILD_ROOT" 2>/dev/null; then
        echo "    removed $BUILD_ROOT"
    elif [ -d "$BUILD_ROOT" ]; then
        echo "    removed $version's build; $BUILD_ROOT keeps files this run did not make:"
        ls -A "$BUILD_ROOT" | sed 's/^/      /'
    else
        echo "    nothing to remove"
    fi
fi

cat <<EOF

Notchline $label ($build) is published.
  Release  $REPOSITORY_URL/releases/tag/$tag
Left for you:
  - On an installed copy: About → Check for Updates → Install, then check About reads
    Version $label ($build).
EOF
[ -z "$build_note" ] || echo "$build_note"
