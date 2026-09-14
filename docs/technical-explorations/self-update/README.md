# Updating Notchline without a Developer ID — technical exploration

| Field | Value |
| --- | --- |
| Status | Researched and measured on 2026-09-13 (macOS 26.6.2 25G83, Xcode 26.6); **built the same day** as [ADR 0022](../../adr/0022-update-through-sparkle-signed-with-our-own-certificate.md), with the feed on `master` (§5.3 option 1). The rehearsal is §10; §7's first-install path is still unmeasured |
| First recorded | 2026-09-13 |
| Question | How can Notchline check for, download and install its own updates while it stays unnotarised, without the user re-trusting it on every update? |
| Audience | Whoever implements the updater and the release pipeline next |
| Recommendation | Sign every release with **one self-signed certificate**, and ship **Sparkle 2** with an EdDSA-signed appcast hosted at a **public** URL |
| Constraint | No Apple Developer Program membership, so no Developer ID and no notarisation. A one-time "Open Anyway" on first install is acceptable; a repeated one is not |

> Later evidence is appended rather than overwriting what is here. Claims are marked **measured** (run on this machine), **source** (read in documentation or source code, linked in §9) or **inferred**.

## 1. The problem

An update has to get past three separate trust gates, and each is keyed on something different:

| Gate | What it keys on | What trips it |
| --- | --- | --- |
| Gatekeeper | The `com.apple.quarantine` attribute | A quarantined, unnotarised bundle: the "could not verify" dialog, then Privacy & Security → Open Anyway |
| TCC (the Automation grant) | The app's **designated requirement** (DR), stored with the grant | New code that does not satisfy the stored DR: the grant is gone and the user is asked again |
| App Management (macOS 13+) | The target app's notarisation and Team ID | Writing inside a protected app's bundle from an app of a different team |

Two further problems sit outside the operating system:

- **There is nothing to download.** Every GitHub release so far is a tag and notes with no assets.
- **Nothing is reachable anonymously.** `soondubu137/notchline` is private (**measured**, `gh repo view`). Release assets and `raw.githubusercontent.com` URLs of a private repository return 404 to a signed-out client. Every release is also a pre-release, so `releases/latest` returns 404 even when authenticated.

## 2. Where Notchline stands today

**Measured**, on the installed `/Applications/Notchline.app` and the current Debug build:

- `Signature=adhoc`, `TeamIdentifier=not set`, and the DR is `cdhash H"…"`. That hash is of this exact build, so no later build can satisfy it.
- The signature carries `com.apple.security.get-task-allow`: the build is signed "to run locally", debug entitlement included.
- The only TCC service the app uses is **Automation**: `NSAppleScript` and `AEDeterminePermissionToAutomateTarget` in `ProcessHostNavigator.swift`. It has no Accessibility, no Screen Recording, no keychain items (`SecItem`) and no `SMAppService`. Only one grant is at stake.
- Nothing outside the bundle points into it. Hook helpers live in `~/Library/Application Support/Notchline/` and are rewritten whenever their bytes differ from the running build ([`docs/artifacts.md`](../../artifacts.md)). Replacing the bundle in place therefore leaves product configuration working.
- The About panel's `AboutUpdateControl` (`NotchOverlayView.swift`) has an intentionally empty action.

## 3. Gate by gate

### 3.1 Gatekeeper: quarantine is opt-in, and an in-app download does not set it

- **Source:** quarantine is applied by the downloading program. A non-sandboxed app sets it only if it declares `LSFileQuarantineEnabled`. On Sequoia and later, Gatekeeper's changes "are only enforced on apps that have been quarantined". Howard Oakley's 26.6.1 test launched a non-quarantined ad-hoc app "normally, without any warning dialog".
- **Measured:** a throwaway, non-sandboxed, ad-hoc-signed app bundle was launched through LaunchServices. It downloaded a zipped app with `URLSession` and unpacked it with `/usr/bin/ditto -x -k`. The temporary download, the moved zip, the unpacked bundle and its executable all carried `com.apple.provenance` and **no `com.apple.quarantine`**.
  - `com.apple.provenance` records which app wrote a file. **Source:** it does not gate launch.
- **Source:** Sparkle strips quarantine from the new bundle regardless (`-[SUFileManager releaseItemFromQuarantineAtRootURL:error:]`, called from `SUPlainInstaller`).
- **Consequence:** "Open Anyway" is needed once, for the copy the user downloads with a browser. An update the app fetches itself does not ask again.
- **Caveat, source:** in the same 26.6.1 test, a *quarantined* ad-hoc app under default settings was sent to the Trash, and "Open Anyway" was not discussed. Apple's support page still documents Open Anyway. Re-check the first-install path on 26.5 before the README's note is relied on (§7).

### 3.2 TCC: the designated requirement decides whether the grant survives

- **Source (TN3127; Quinn, Apple DTS):** an ad-hoc DR is "tied to that specific version of the code", so "macOS is unable to tell that version N+1 of your app is the 'same code' as version N". Every ad-hoc update today loses the Automation grant.
- **Source (Apple Security `drmaker.cpp`):** for a certificate not issued by Apple, `codesign` pins the certificate's SHA-1 hash in the DR. The form is `certificate leaf = H"…"`, or `certificate root = H"…"` when the certificate carries an Organisation field.
- **Measured:** a self-signed certificate was created with OpenSSL (`extendedKeyUsage=critical,codeSigning`, 10 years) and imported into a throwaway keychain. Two copies of the Debug build, one with an extra resource, were signed with it. Results:
  - The cdhashes differ (`7bdac47e…`, `3c5cd717…`).
  - Both DRs read `identifier "com.yinfenglu.Notchline" and certificate leaf = H"83d91321…"`.
  - `codesign --verify -R=<v1's DR>` accepts v2.
  - The same check with the installed build's `cdhash` DR rejects it, as expected.
- **Measured:** the certificate stays **untrusted**. `security find-identity` reports `CSSMERR_TP_NOT_TRUSTED`, yet `codesign -s` signs with it once its keychain is on the user search list; `--keychain` alone reports "no identity found".
  - No trust setting has to be changed, on the developer's Mac or the user's.
  - A DR is a hash match, not a trust evaluation. **Inferred** for TCC's check, which uses the same `SecCode` requirement API.
- **Inferred, but consistent with a third-party report:** TCC grants survive an update signed with the same certificate. `ocade-dictee` switched from ad-hoc to a self-signed certificate and confirmed that its Accessibility grant survived an update.

Caveats of a self-signed identity:

- **The certificate *is* the identity.** A lost or reissued certificate is a new DR: every user is asked again once, and Sparkle's code-signing anchor is lost (§4). Export the certificate and private key as a `.p12` and keep it offline.
- **A leaked key** lets someone produce code that TCC treats as Notchline. Store it like a password.
- **Expiry.** Signature checks ignore certificate expiry unless the caller passes `kSecCSConsiderExpiration` (**source**). Issue the certificate for 20+ years so the question never arises.
- **Hardened runtime** buys nothing without notarisation. If it is ever enabled:
  - Apple Events need `com.apple.security.automation.apple-events` (**source**).
  - Library validation would refuse an embedded framework with no Team ID (**inferred**).
  - Leave it off.
- **Rejected alternative: a free Apple ID "Apple Development" certificate.**
  - It does give a stable, name-based DR and a Team ID.
  - Gatekeeper still treats the app as unnotarised.
  - The Xcode and Apple SDKs Agreement licenses Apple's certificate services "solely to test and develop"; distributing to users with it reads as outside that licence.
  - It expires yearly.

### 3.3 App Management: protects notarised apps, and a whole-bundle swap is a move

- **Source (WWDC22 10096; Jeff Johnson; Sparkle maintainer):** the protection covers notarised apps that Gatekeeper has scanned. Apps of the same team can update each other. `NSUpdateSecurityPolicy` names other teams by Team ID only, so it does nothing here. Johnson found a notarised app modifiable before its first launch.
- **Source (Quinn):** build a complete new copy and move it into place, to avoid "app bundle protection entanglements".
- **Measured.** Throwaway apps were launched through LaunchServices (`open -n`), under `/private/tmp`, with no quarantine. The two write tests were: write a file inside the target bundle; copy the bundle, rename the original aside, move the copy into place and delete the original.

  | Target | Writer | Write inside bundle | Copy, rename aside, move into place |
  | --- | --- | --- | --- |
  | Copy of a notarised Developer ID app, launched once | Ad-hoc app | **EPERM** | Succeeded |
  | Same copy, never launched | Ad-hoc app | Succeeded | Succeeded |
  | Self-signed app, launched once | App signed with the same certificate | Succeeded | Succeeded |
  | Self-signed app, launched once | Ad-hoc app | Succeeded | Not recorded |
  | A different ad-hoc app, launched once | Ad-hoc app | Succeeded | Not recorded |
  | Its own running bundle, self-signed | Itself | Succeeded | Succeeded |
  | Its own running bundle, ad-hoc | Itself | Succeeded | Succeeded |

  - The first row is the positive control. The protection is live on this Mac and is not tied to `/Applications`.
  - Apps with no Team ID were not protected, even after launching.
  - Even for the protected app, swapping the whole bundle succeeded. That is the operation Sparkle performs (`renamex_np(RENAME_SWAP)`).
- **Not measured:** the exact user path, a browser download approved with Open Anyway and living in `/Applications`. Approval does not notarise an app, so it is expected to behave like the unprotected rows (**inferred**), but §7 checks it.

## 4. Mechanism options

| | Sparkle 2 (2.10.0, released 2026-09-13) | Hand-rolled updater | Homebrew cask |
| --- | --- | --- | --- |
| Works without a Developer ID | Yes. EdDSA is always sufficient; a DR match is a second, independent anchor (**source**, `SUUpdateValidator`) | Yes | **No** for the official tap. Casks that fail Gatekeeper are disabled from September 2026 and `--no-quarantine` is gone (**source**). A private tap still installs quarantined |
| In-app check and install | Yes | Yes | No; the user runs `brew upgrade` |
| Licence | MIT, compatible with GPL-3.0-or-later | — | — |
| Cost | First package dependency in the project, and a framework plus helpers in the bundle | Several hundred lines plus tests, and every edge case below | — |

Edge cases Sparkle already handles (**source**) that a hand-rolled updater would have to re-implement:

- **App Translocation:** Sparkle refuses and asks the user to move the app to Applications.
- **Atomic swap:** `renamex_np(RENAME_SWAP)`, with a move-and-restore fallback.
- **Unwritable install location:** an authorised installer (`AuthorizationCreate`).
- **Relaunch:** relaunch after the old process exits (`Autoupdate`'s termination listener).
- **Downgrades and removed trust:** refuses downgrades, and refuses an update that removes the EdDSA key or code signing.
- **Bundle metadata:** preserves owner, group and Finder tags.
- **Scheduling:** the check timer and gentle reminders for an accessory app.
- **Keys:** EdDSA key rotation, allowed when the code signature matches.

Sparkle's documented weak spot for this setup is ad-hoc signing. "Matching signatures on ad-hoc signed apps does *not* work" (Sparkle's own tests), which leaves EdDSA as the only anchor, and a lost EdDSA key then means no further update can ever be delivered. A self-signed certificate removes that weakness, for the same reason it keeps the TCC grant.

## 5. Proposed design

### 5.1 Signing

1. **Create the certificate once.** One self-signed code-signing certificate (for example `CN=Notchline Release`, 20+ years, EKU `codeSigning`) in the developer's login keychain. Back up the `.p12` offline.
2. **Re-sign after the build.** A release script builds `Release`, then re-signs inside out: Sparkle's nested helpers (`Autoupdate`, `Updater.app`, and the XPC services unless they are stripped), then `Sparkle.framework`, then the app. The script signs with the certificate by name, without `get-task-allow`, and with hardened runtime off.
   - Re-signing afterwards, rather than setting `CODE_SIGN_IDENTITY`, avoids depending on whether Xcode's identity picker accepts an untrusted certificate (not tested).
3. **Verify before publishing.** `codesign --verify --strict --deep`, plus `codesign -d -r-` compared against the recorded DR, so a certificate mix-up cannot ship.

### 5.2 Updater

- **Package and wiring.** Sparkle 2 via Swift Package Manager, and one `SPUStandardUpdaterController` owned by the app delegate. `AboutUpdateControl` calls `checkForUpdates(_:)` and binds its enabled state to `canCheckForUpdates`.
- **Info.plist:**
  - `SUFeedURL`: permanent; see §5.3.
  - `SUPublicEDKey`.
  - `SUEnableAutomaticChecks`: set it, rather than let Sparkle ask on the second launch.
  - `SUScheduledCheckInterval`: the default is 86400.
- **Accessory app.** Notchline is `LSUIElement`, so implement `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders`; otherwise Sparkle logs a warning, and a scheduled update window can open behind other apps.
- ~~**Presentation.** Start with Sparkle's standard windows. A notch-drawn `SPUUserDriver` is a separate design question.~~ **Decided 2026-09-13 in [`updates-on-the-notch.md`](../../updates-on-the-notch.md):** a notch-drawn `SPUUserDriver`, with a dot on the About mark and the whole update in About's control row.
- **Non-sandboxed.** The XPC services are unnecessary and can be removed from the bundle.
- ~~**Settings** gains an "Automatically check for updates" switch bound to `automaticallyChecksForUpdates`.~~ **Decided 2026-09-13:** a fourth `Updates` pane, which also has a background-downloads switch, off by default ([`updates-on-the-notch.md`](../../updates-on-the-notch.md) §5).

### 5.3 Hosting — the user's decision

`SUFeedURL` is compiled into every shipped copy, so it has to stay valid for as long as old copies exist. The repository is private today (§1), which leaves three options:

1. **Make `soondubu137/notchline` public.** Zips become release assets. `appcast.xml` is committed to `master` and read from `raw.githubusercontent.com`, not from `releases/latest/download/…`, because every release is a pre-release. This is the simplest option.
2. **Keep the source private and add a public releases repository** (or GitHub Pages) holding the appcast and the zips.
3. **A domain the developer controls**, with the appcast on any static host. This is the most durable URL, and the most to run.

### 5.4 Release motion additions

These extend the current cut (version settings, README badge, `CHANGELOG.md` section, tag, pre-release):

- **Archive.** `ditto -c -k --sequesterRsrc --keepParent Notchline.app Notchline-<version>.zip`.
- **Appcast.** Run `generate_appcast` (or `sign_update` plus a hand-edited item), with the release notes linked or embedded from the changelog section.
- **Publish.** Upload the zip to the release, and commit the appcast, making it the cut's fourth file.

### 5.5 Documents that change with the implementation

- **`docs/artifacts.md`:** Sparkle's preference keys (`SULastCheckTime`, `SUEnableAutomaticChecks`, …) and its download cache under `~/Library/Caches/com.yinfenglu.Notchline/`.
- **README:**
  - "Files and data" gains a periodic network request to the feed URL.
  - The installation note keeps Open Anyway for the first install only.
- **An ADR** for the first third-party dependency and for the signing identity, including the key-custody rule.

## 6. Migration

- **0.4.3 has no updater.** The first version that has one is installed by hand. No release has ever carried a download, so in practice every outside user starts on that version.
- **One last Automation prompt.** The move from ad-hoc to the self-signed certificate is itself a DR change, so existing installs, the developer's included, are asked for Automation once more. From then on the DR is fixed.
- **Sparkle accepts the change of signature.** It is not a removal of signing, and EdDSA vouches for the update (**source**, `passesBasicUpdatePolicy…`).

## 7. Before shipping: the end-to-end check nothing above covers

Run once on macOS 26.5, preferably in a second user account, with two consecutive signed builds N and N+1 on the chosen host:

1. Download build N's zip with Safari and confirm it is quarantined (`xattr`). Confirm Gatekeeper offers **Open Anyway** rather than only Move to Trash (the §3.1 caveat).
2. Move it to `/Applications`, open it, click a Claude Code row hosted in Terminal, and allow Automation.
3. Publish N+1. Use About → Check for Updates and install.
4. Expect all of the following:
   - No Gatekeeper dialog.
   - No "prevented from modifying apps" notification, and Notchline absent from Privacy & Security → App Management.
   - The new bundle without `com.apple.quarantine`.
   - `codesign -d -r-` unchanged.
   - Clicking the same row focuses the tab **without** an Automation prompt.
5. Also check that Sparkle's `gktool scan` step on the unnotarised bundle does not stall or fail the install (not verified).

If step 4 shows the App Management prompt, the fallback is still a one-time grant in Privacy & Security, not a per-update one.

## 8. How the measurements were taken

The apparatus was deleted afterwards, and nothing touched `/Applications`, trust settings or TCC.

- **Certificate.** OpenSSL made the key and certificate. A `.p12` exported with `-legacy` was imported into a keychain created under the session scratchpad. That keychain was placed on the user search list for the duration of each signing command, the list was restored afterwards, and the keychain was then deleted.
- **Probes.** Each probe was a single-file Swift executable in a hand-made `.app` with `LSUIElement`, launched with `open -n` so that LaunchServices, not the shell, owned it. It wrote a log of each file operation's result.
- **Update archive.** The zipped update was served from `python3 -m http.server` on `127.0.0.1`.
- **Positive control.** An App Management control was needed because a target under `/private/tmp` is not obviously in scope. Without the launched notarised copy's EPERM, every "Succeeded" in §3.3 would have been meaningless.
- **Cleanup.** Probe bundles were unregistered with `lsregister -u` before deletion.

## 9. Sources

- Apple TN3127, Inside Code Signing: Requirements — <https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements>
- Quinn on ad-hoc DRs and TCC — <https://developer.apple.com/forums/thread/795739>; on quarantine being opt-in — <https://developer.apple.com/forums/thread/730314>; on replacing a bundle by moving a copy — <https://developer.apple.com/forums/thread/779326>
- Apple Security, `drmaker.cpp` — <https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/drmaker.cpp>
- `LSFileQuarantineEnabled` — <https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled>; `NSUpdateSecurityPolicy` — <https://developer.apple.com/documentation/bundleresources/information-property-list/nsupdatesecuritypolicy>
- WWDC22 10096, What's new in privacy — <https://developer.apple.com/videos/play/wwdc2022/10096/>
- Jeff Johnson, App Management — <https://lapcatsoftware.com/articles/AppManagement.html>
- Howard Oakley — <https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/>, <https://eclecticlight.co/2026/08/11/how-can-you-run-code-that-hasnt-been-notarised/>, <https://eclecticlight.co/2025/12/05/quarantine-macl-and-provenance-what-are-they-up-to/>
- Apple, opening apps from unidentified developers — <https://support.apple.com/en-us/102445>
- Sparkle 2.10.0 source (`SUUpdateValidator.m`, `SUCodeSigningVerifier.m`, `SUPlainInstaller.m`, `SUFileManager.m`, `SPUStandardUserDriver.m`) — <https://github.com/sparkle-project/Sparkle>; maintainer on accounts — <https://github.com/sparkle-project/Sparkle/discussions/2310>; on App Management — <https://github.com/sparkle-project/Sparkle/discussions/2881>; sandboxing and XPC — <https://sparkle-project.org/documentation/sandboxing/>
- ocade-dictee, ad-hoc to self-signed — <https://github.com/ocade-graciet-system/ocade-dictee/issues/29>
- Homebrew 5.0.0 — <https://brew.sh/2025/11/12/homebrew-5.0.0/>; Gatekeeper cask deadline — <https://github.com/Homebrew/brew/issues/20755>
- Xcode and Apple SDKs Agreement — <https://www.apple.com/legal/sla/docs/xcode.pdf>

## 10. Rehearsal record (2026-09-13, after the build)

This rehearsal used the committed scripts with a throwaway keychain and a throwaway EdDSA key file, passed through the scripts' environment overrides. The user's keychain, `/Applications` and the running Debug Notchline were not touched.

- **`create-release-identity.sh` ran end to end with no prompt.**
  - It wrote a `.p12` backup that opens with the chosen passphrase.
  - It recorded `identifier "com.yinfenglu.Notchline" and certificate leaf = H"…"`.
  - A second run refused.
  - Two things the first draft got wrong:
    - `security import` refuses the PKCS#8 key `openssl req` writes ("Unknown format in import") and accepts the traditional RSA form.
    - Sparkle 2.10's key file is the bare 32-byte seed, base64. Seed plus public key is rejected, with the self-contradicting message "must be 64 bytes … Instead it is 64 bytes".
- **`build-release.sh` built Release twice (builds 16 and 17).**
  - Every Mach-O in the bundle ended up signed as `Notchline Release`, flags `0x0`.
  - `Sparkle.framework` no longer contains `XPCServices`.
  - Of the entitlements, only `files.user-selected.read-only` remained; `get-task-allow` is gone.
  - The requirement check passed, and `codesign --verify --strict --deep` reported "satisfies its Designated Requirement".
  - The feed gained two items, newest first, carrying the 0.4.3 changelog section as Markdown.
- **The install path, on a stand-in host.** Relaunching a real Notchline outside a redirected home would have bound the live hook sockets of the Debug copy on screen, so an `LSUIElement` host linking the same `Sparkle.framework` was used instead. It went through the same `sign_app`, `ditto`, `sign_update` and `add_feed_item.py` steps.
  - Build 1 found build 2, and Autoupdate logged "OK: EdDSA signature is correct for update".
  - The update installed in place and relaunched as build 2, all within one second.
  - The installed bundle carries no `com.apple.quarantine`, still satisfies the same certificate requirement, and verifies strictly.
  - `syspolicyd` registered each launched bundle "for protection" and, after the scan, logged "Unregistering bundle for protection after scan … (team: (null))". This is the log-level reason §3.3's rows without a Team ID were never protected.
  - Nothing logged a denial.
- **Notchline itself, re-signed.** The Release build (build 17) was launched for 7 seconds under `CFFIXED_USER_HOME` and `HOME` pointing at a throwaway home.
  - It stayed up, and Sparkle started without a configuration error.
  - The first launch checked the feed **at once**; with no server listening, that failed silently to the log.
  - Sparkle wrote `SUHasLaunchedBefore` and `SULastCheckTime` into the real preferences domain, which `CFFIXED_USER_HOME` does not redirect. They were removed afterwards, and the domain diffed equal to its snapshot.
- **`AppUpdaterTests`' feed test was checked against bad feeds.**
  - With the rehearsal's localhost URLs it fails, and with an older build listed first it fails; with release URLs in the right order it passes.
  - `#expect(!(x ?? "").isEmpty)` reported a failure while printing the value present, so the check is written `x?.isEmpty == false`.

## 11. End-to-end rehearsal in the real app (2026-09-14)

§7's check was run on this Mac (macOS 26.6.2). Two Release builds of `master` at `e949578`, 0.4.90 (90) and 0.4.91 (91), were made with `build-release.sh`, using the real bundle ID. A throwaway `Notchline Rehearsal` certificate and EdDSA key signed them, and the feed was served from `127.0.0.1`. The only departure from §7: the install went into `~/Applications`, which left the user's older copy in `/Applications` alone.

| §7 step | Result |
| --- | --- |
| Safari download | Unzipped with `com.apple.quarantine` (`01c3;…;Safari`) and the rehearsal certificate's requirement |
| Gatekeeper | The "could not verify" prompt, then **Open Anyway was offered and worked** for an untrusted self-signed, unnotarised app. §3.1's caveat is answered for 26.6.2. `syspolicyd`: "Unregistering bundle for protection after scan … (team: (null))" |
| Automation | Granted from 0.4.90 after `tccutil reset AppleEvents com.yinfenglu.Notchline` (see the caveat below) |
| Update | Scheduled check → dot → About 04 → Install → 06 → Autoupdate "OK: EdDSA signature is correct for update" → 08 held by a running Turn → relaunched by itself when it finished |
| After the relaunch | 0.4.91 (91) in place, **no `com.apple.quarantine`**, the same requirement, valid signature, only the overlay window. Gatekeeper's re-scan showed no prompt |
| Automation after the update | The same Terminal row came forward with **no prompt**; `tccd` answered `authValue: 2` to the new process |
| App Management | Notchline not listed in Privacy & Security; no "prevented from modifying apps" |

**Caveat: a grant that should not have matched, but did.** Before the reset, clicking a Terminal row in 0.4.90 prompted nothing: `tccd` answered `authValue: 2` from a record that predated the rehearsal certificate. That record's stored requirement could not be read, because `TCC.db` needs Full Disk Access. So on 26.6.2, an Apple Events grant made by one signer answered for a build signed by another. Either the record held no requirement, or Apple Events does not enforce one here.

The design is unaffected, because a stable certificate is right either way: Apple documents requirement matching, and Accessibility enforces it. But §3.2's claim that ad-hoc updates *lose* the Automation grant is unconfirmed for Apple Events on this machine. Settling it would take one Full Disk Access read of the record, or a fresh grant made by an ad-hoc build and tested against a second ad-hoc build.

**Also noted.**
- The rehearsal copy did not check at its first launch: an earlier run had written `SULastCheckTime` 13 minutes before. Sparkle's once-a-day schedule is per preferences domain, shared by every copy with the bundle ID.
- A rehearsal must clear that key to watch a scheduled check, and restore the domain afterwards. It was restored here, to the snapshot taken before the rehearsal.

## 12. First install from the public release (2026-09-14)

The repository was made public after 0.5.0 Beta was published, and the real release was checked from outside, then installed as a user would.

**Signed out.** Every read below used `curl` with no credentials.

| Check | Result |
| --- | --- |
| Repository | `private: false` from the anonymous API |
| Feed | `raw.githubusercontent.com/…/master/appcast.xml`: HTTP 200, byte-identical to `appcast.xml` on `master` |
| Archive | The enclosure URL redirected to `release-assets.githubusercontent.com`, HTTP 200. Its 3,973,062 bytes match the feed's `length`, and its SHA-256 matches the release asset's digest. No `com.apple.quarantine` |
| EdDSA | Valid against the `SUPublicEDKey` inside the downloaded bundle, using CryptoKit alone. The same file with one flipped byte was rejected |
| Bundle | 0.5.0 (17). `codesign --verify --deep --strict` passes. The requirement equals `scripts/release/designated-requirement.txt`. No Team ID, no `get-task-allow`, no Sparkle XPC services. `spctl` rejects it, as expected without notarisation |

**Installed.** The user downloaded the zip in a browser; its `com.apple.quarantine` names Chrome. They moved the app to `/Applications` and opened it. Open Anyway worked, and About → Check for Updates reported the copy up to date.

**Automation was not asked for. That is §11's caveat again, under cleaner conditions.** Clicking a Terminal row selected the tab with no prompt. At the click, Terminal made `TCCAccessRequestIndirect` calls for `/Applications/Notchline.app`, and `tccd` answered from the database: `kTCCServiceAppleEvents … com.apple.Terminal, authValue: 2`. The only grant on file was the one §11 made after its `tccutil reset`, from 0.4.90, signed with the `Notchline Rehearsal` certificate. This copy is signed with `Notchline Release`, a different certificate and requirement. Unlike §11, the grant's origin is known: a fresh prompt under a known signer answered for another signer.

The same `tccd` did compare requirements for another service at this launch. It logged "Failed to match existing code requirement for subject com.yinfenglu.Notchline and service kTCCServiceScreenCapture" for WindowServer's preflight. Requirement matching works in this daemon; it just did not stop this Apple Events grant. Without Full Disk Access, the stored `csreq` still cannot be read.

**What this changes.**
- The first-install Automation prompt was not exercised on this Mac, because a grant for the bundle ID already existed. A machine that never ran Notchline has no record, and it prompts.
- 0.5.0's changelog says the grant from earlier, ad-hoc versions "does not carry over". On 26.6.2 that has now been contradicted twice, so it is at most a possibility.
- The stable certificate is still right: it is what Apple documents, and it is what TCC enforces for other services.

**Automation, prompted for real.** The user then ran `tccutil reset AppleEvents com.yinfenglu.Notchline`. The next Terminal row click brought up the prompt, and they allowed it. So 0.5.0 holds a grant made under its own certificate.

### 12.1 The first update from the public feed (0.5.0 → 0.5.1)

0.5.1 Beta (18) was cut with one fix (issue #69), built and signed by `build-release.sh`, and uploaded. The feed was pushed at 09:56. `raw.githubusercontent.com` served the old feed (`max-age=300`, `x-cache: HIT`) until 10:01:34, when it began serving the committed file.

| Check | Result |
| --- | --- |
| Offer | About → Check for Updates on the installed 0.5.0 found 0.5.1. The user pressed Install. No prompt of any kind: no password, no App Management, no Open Anyway |
| Install | Autoupdate: "OK: EdDSA signature is correct for update" at 10:03:03. It also logged "bookmark data for update download is stale.. but still continuing", which did not stop the install. The new process started at 10:03:04 |
| Bundle | `/Applications/Notchline.app` 0.5.1 (18), signature valid, satisfies `designated-requirement.txt` |
| Quarantine | The attribute Chrome put on 0.5.0 is gone from the bundle and from every file in it. Only `com.apple.provenance` remains |
| Gatekeeper | `syspolicyd` scanned the new bundle (`evaluateScanResult: 2`, team null) and showed nothing |
| App Management | Nothing for Notchline. The one `kTCCServiceSystemPolicyAppBundles` request in the window came from Claude's desktop app (`com.anthropic.claudefordesktop`) |
| Automation | The row click worked with no prompt; `tccd` answered `kTCCServiceAppleEvents … com.apple.Terminal, authValue: 2` at 10:03:23 |
| Leftovers | Sparkle's `Installation` and `PersistentDownloads` caches are empty. `updateReceiptBuild` = 18, so About can show what's new once |

This is the path §7 set out to prove, measured on a real release: an update installed in place into `/Applications` from GitHub. Nothing asked the user for anything, and every permission stayed.
