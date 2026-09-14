# Update through Sparkle, signed with a certificate of our own

Notchline checks a feed on `master` (`appcast.xml`) once a day and from About → Check for Updates, and installs what it finds with **Sparkle 2**, the project's first package dependency. Every release is re-signed with **one self-signed certificate**, `Notchline Release`, and every archive carries an **EdDSA signature**. The research and measurements are in [`technical-explorations/self-update`](../technical-explorations/self-update/README.md). This record is the decision and what it binds.

## Why this shape

There is no Apple Developer Program membership, so there is no Developer ID and no notarisation. The constraint is that a user trusts the app once, on first install, and never again.

That rules out three things an update could otherwise trip:

1. **Gatekeeper asks again for a quarantined copy.** An app's own `URLSession` download is not quarantined (measured), and Sparkle strips the attribute regardless. A browser download is quarantined, so "Open Anyway" stays the one-time cost of the first install.
2. **TCC drops the Automation grant when the designated requirement changes.**
   - Ad-hoc signing makes that requirement the build's cdhash, which no later build satisfies.
   - A self-signed certificate makes it `identifier "com.yinfenglu.Notchline" and certificate leaf = H"<certificate hash>"`, which every build signed with that certificate satisfies (measured).
   - Caveat, 2026-09-14: for Apple Events on macOS 26.6.2, a grant made under another signer still answered "allowed", twice: in the rehearsal, and when 0.5.0 answered from the rehearsal certificate's fresh grant. So the loss is unconfirmed there. A stable certificate is right either way (exploration §11–§12).
3. **App Management blocks writes into protected apps.** It protects apps with a Team ID. A launched bundle without one is registered for protection and then unregistered after its scan (`syspolicyd`: "Unregistering bundle for protection after scan … team: (null)", measured during the rehearsal). Even for a protected app, Sparkle's whole-bundle swap is a move, not a write inside the bundle.

## What it binds

- **The feed URL is permanent.** `NOTCHLINE_UPDATE_FEED_URL` is compiled into every copy, so `appcast.xml` stays at the repository root on `master`, and the repository stays readable anonymously.
  - `releases/latest/download/…` is deliberately not used, because every release is a pre-release.
  - `AppUpdaterTests` pins the URL, the file and the feed's shape.
- **The certificate is never replaced.**
  - `scripts/release/designated-requirement.txt` records its requirement, and `build-release.sh` refuses to package a bundle that does not match it.
  - A replacement would cost every user their Automation grant once, and would remove Sparkle's second trust anchor.
- **The EdDSA key is never replaced without that anchor.**
  - Sparkle accepts an update if its archive's signature verifies against the running copy's `SUPublicEDKey`, or if the new bundle satisfies the running copy's designated requirement.
  - With both in place, either key can be rotated by a release signed with the other.
  - Losing both ends updates for every installed copy.
- **Both private keys are backed up outside the repository.** `create-release-identity.sh` writes the backups and refuses to run a second time.
- **A build without a public key never starts the updater.** Without a key there is nothing to verify an update against, and Sparkle would put up an alert on every launch (`AppUpdater.start()`).
- **Debug builds do not check on their own** (`NOTCHLINE_UPDATE_CHECKS_AUTOMATICALLY = NO`), so a development build is not offered a release to replace itself with. The About button still checks.
- **Hardened runtime stays off.** It buys nothing without notarisation. It would refuse Apple Events without `com.apple.security.automation.apple-events`, and with no Team ID its library validation would refuse the embedded framework.
- **Sparkle's XPC services are removed** at signing time. They exist for sandboxed hosts, and Notchline is not one.

## Publishing order

The cut commit, tag and pre-release stay as they were. Then:

1. `scripts/release/build-release.sh` on the tagged commit.
2. `gh release upload v<version> build/release/<version>/Notchline-<version>.zip`.
3. Commit and push `appcast.xml`, in a commit of its own.

The upload comes first. A feed pushed ahead of its archive offers every copy a download that does not exist yet.

## Considered and rejected

- **A hand-rolled updater** (GitHub API, CryptoKit, a swap script). It would have to re-implement what Sparkle already handles:
  - refusing a translocated copy;
  - the atomic swap and relaunch;
  - an unwritable install location;
  - downgrade refusal;
  - key rotation;
  - gentle reminders for an accessory app.
- **Ad-hoc signing plus Sparkle.** It works, with EdDSA as the only anchor, but every update would still cost the Automation grant.
- **A free Apple ID "Apple Development" certificate.** Its licence limits it to test and development. It expires yearly, and Gatekeeper treats the app as unnotarised all the same.
- **A Homebrew cask.** From September 2026 the official tap disables casks that fail Gatekeeper, and `brew upgrade` is not an in-app update.
- **A feed on GitHub Pages or a separate releases repository.** Either works, but each is one more thing to keep alive for a URL that can never change. The repository itself is going public.

## What is still unmeasured

~~The path a real user takes: a Safari download, Open Anyway, the app moved to `/Applications`, Automation allowed, then an update. The rehearsal covered every piece of that except the quarantine-and-approval start and the Terminal row click. The checklist is §7 of the exploration.~~ **Measured 2026-09-14** in the real app, installed in `~/Applications` rather than `/Applications` (exploration §11): the whole path held. ~~Nothing is left but the first update from the public GitHub feed, which needs two real releases.~~ **Measured 2026-09-14**, 0.5.0 → 0.5.1 in `/Applications` (exploration §12.1). It installed with no prompt, no quarantine and no App Management, and Automation was kept. Nothing on this path is unmeasured.
