# TestFlight setup

Getting Sunnie Days onto an iPhone **without owning a Mac**.

A macOS runner on GitHub Actions does the building and signing, App Store
Connect processes the result, and the phone installs it from the TestFlight app.
Nothing in the loop needs a Mac in your hands.

Everything here is one-time. After it, shipping a build is: open the Actions tab,
press **Run workflow**, wait, install.

> **Requires a paid Apple Developer account** ($99/year). The free tier cannot
> upload to App Store Connect at all.

---

## What you are setting up

| Piece | Where it lives | Why |
|---|---|---|
| A bundle identifier | developer.apple.com | Names the app to Apple. Must be globally unique. |
| An app record | App Store Connect | The thing builds get uploaded *into*. |
| An API key | App Store Connect | Lets CI sign and upload without your password. |
| Five repository secrets | GitHub | How the workflow learns all of the above. |
| Yourself as a tester | App Store Connect | Otherwise the build uploads and nobody can install it. |

---

## 1. Register a bundle identifier

developer.apple.com → **Certificates, Identifiers & Profiles** → **Identifiers**
→ **+** → *App IDs* → *App*.

- **Description:** Sunnie Days
- **Bundle ID:** *Explicit*, and something you own the domain-shape of —
  `com.yourname.sunniedays.app` is fine. It has to be globally unique across the
  App Store, so `com.sunniedays.app` may well be taken.

Leave every capability switch **off**. The app ships with its entitlements
inactive on purpose (ADR-012), so turning them on here without doing the rest of
§5 of `DEVICE_BRING_UP.md` only creates a mismatch that fails signing.

> **Note the prefix.** If your bundle ID is `com.yourname.sunniedays.app`, then
> the prefix you will put in the secrets below is `com.yourname.sunniedays` —
> without `.app`. The build config appends that itself, and it derives the
> widget and Watch identifiers from the same prefix.

## 2. Create the app record

App Store Connect → **Apps** → **+** → **New App**.

- **Platform:** iOS
- **Name:** anything unused across the whole App Store. "Sunnie Days" may be
  taken; the name here is only what shows in TestFlight for now and can be
  changed later.
- **Bundle ID:** the one from step 1
- **SKU:** any private string — `sunniedays-001`
- **User access:** Full Access

This must exist before the first upload. An upload with no app record fails with
an error that does not mention the app record.

## 3. Create an API key

App Store Connect → **Users and Access** → **Integrations** tab → **App Store
Connect API** → **Team Keys** → **+**.

- **Name:** GitHub Actions
- **Access:** **App Manager** — a lower role cannot upload builds

Then, in this order, because Apple only offers the file once:

1. **Download the `.p8` file.** It is offered exactly once and never again. Lose
   it and you revoke the key and start this step over.
2. Copy the **Key ID** — ten characters, shown in the row.
3. Copy the **Issuer ID** — a UUID, shown above the table. It is the same for
   every key on the team.

## 4. Find your Team ID

developer.apple.com → **Membership details**. Ten characters, and not the same
as the Issuer ID from the previous step.

## 5. Add five repository secrets

GitHub → the repository → **Settings** → **Secrets and variables** → **Actions**
→ **New repository secret**, five times.

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | The ten characters from step 4 |
| `SUNNIE_BUNDLE_ID_PREFIX` | Your prefix from step 1, **without** the trailing `.app` |
| `ASC_KEY_ID` | The ten-character Key ID from step 3 |
| `ASC_ISSUER_ID` | The issuer UUID from step 3 |
| `ASC_KEY_P8` | The **entire contents** of the `.p8` file |

For `ASC_KEY_P8`, open the `.p8` in any plain text editor and paste everything,
including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`
lines. The workflow also accepts the base64 of the file if that is easier to
produce on your machine — it detects which one it was given, so you cannot get
this wrong in a way that is hard to diagnose.

## 6. Add yourself as an internal tester

App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** next
to Testers → add your own Apple ID.

Internal testers skip Beta App Review entirely, so builds are installable within
minutes of processing rather than after a review round. Do this now; it is the
step most easily forgotten, and its symptom is a build that uploads perfectly and
then never appears on the phone.

## 7. Run it

GitHub → **Actions** → **TestFlight** → **Run workflow**. Optionally write a note
for what to test.

The job takes roughly 20–40 minutes, most of it compiling. Then App Store Connect
processes for another 5–15. On the phone: install **TestFlight** from the App
Store, sign in with the same Apple ID, and Sunnie Days is there.

---

## What you will be testing

Set expectations before you install, because two of these look exactly like bugs
and are neither:

- **Sunnie is a grey circle with a symbol in it.** No production artwork exists
  (`AssetsSource/ASSET_MANIFEST.md`). The app icon is a placeholder sun for the
  same reason — App Store Connect refuses an upload with no icon at all.
- **There is no music.** Seven tracks are declared against files nobody has
  recorded, and the director skips them. The synthesised ambiences and bells do
  play, and those are worth trying.
- **No Health, no widgets, no iCloud sync.** Entitlements ship inactive. The app
  is local-only and complete that way; turning them on is §5 of
  `DEVICE_BRING_UP.md`.
- **No Watch app.** This uploads the iPhone build alone.

Everything else is real: the plant care loop, all three branded day cycles,
wellness and journal, travel, meals, the seven games, collections, Sunnie's Home.
Most of it has never been run by anyone, which is the point of installing it.

## When it fails

The workflow prints a filtered error list and the three most likely causes on any
failure, and uploads the full `xcodebuild` logs as an artifact. Beyond those:

| Symptom | Cause |
|---|---|
| `No profiles for '...' were found` | The bundle prefix secret does not match the identifier registered in step 1. |
| `The provided entity includes an attribute with a value that has already been used` | That build number was already uploaded. Re-run — the number comes from the run count and advances by itself. |
| `Authentication credentials are missing or invalid` | The API key lacks App Manager, or `ASC_KEY_ID` and `ASC_ISSUER_ID` are swapped. |
| `App Store Connect API key not found` | `ASC_KEY_P8` did not decode. The workflow says so explicitly before it gets this far. |
| Build uploads, never appears in TestFlight | Step 6 was skipped, or processing is still running. |
| `Missing Compliance` in App Store Connect | Should not happen — `ITSAppUsesNonExemptEncryption` is declared in `Info.plist`. If it does, answer once in the web form and report it. |

## What this does not cover

- **The Watch app.** It needs the watchOS SDK downloaded onto the runner, which
  is several gigabytes per run. `ci.yml` has a manual `build-watch` job for
  compiling it; putting it in a TestFlight build is a separate piece of work.
- **Public TestFlight links.** External testers require Beta App Review. Internal
  testing is enough for one person and avoids the wait.
- **App Store release.** Screenshots, privacy nutrition labels, and review are a
  different exercise entirely.
