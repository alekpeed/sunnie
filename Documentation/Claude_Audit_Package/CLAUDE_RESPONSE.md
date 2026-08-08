# Response to the Codex audit

Every finding below was checked against the source before being accepted or
rejected. The audit was treated as a second opinion, not as instructions.

**Baseline.** The audit was performed on commit `d5a005c`, which already contains
the three defects found by the first Linux compile. Its "441 checks passed" and
this repository's 441 are the same number, so the two reviews agree on the
starting state.

## Verdicts

| # | Finding | Verdict |
|---|---|---|
| RB-1 | The full app has never been built | **Correct** |
| RB-2 | Migration from older stores never proven | **Correct** |
| RB-3 | Apple-service promises don't match the default setup | **Correct**, and deliberate (ADR-012) |
| RB-4 | No erase-all in Settings | **Correct** — and it contradicts a written promise |
| RB-5 | No locked-device rule for private files | **Correct** — now partly fixed |
| HP-1 | Export leaves temp copies; failure is silent | **Correct on both halves** — fixed |
| HP-2 | Delete buttons hide failures | **Correct** — 10+ sites, not fixed |
| HP-3 | Journal deletion is a hidden soft delete with no purge | **Mostly wrong** |
| HP-4 | Photo-library permission unnecessary | **Correct** — fixed |
| HP-5 | Camera permission unused | **Wrong, and acting on it would crash the app** |
| HP-6 | Documents disagree with themselves | **Correct** — fixed |
| HP-7 | CI has no proven successful run | **Correct** |

## The two rejections, in detail

### HP-5 — camera permission is *not* unused

The audit reports "no camera capture was found" and recommends removing
`NSCameraUsageDescription`.

`Apps/iOS/Features/Jungle/Components/PlantQRViews.swift` contains a full
`AVCaptureSession` — `AVCaptureDevice.default(for: .video)`,
`AVCaptureDeviceInput`, `AVCaptureVideoPreviewLayer`, and an
`AVCaptureMetadataOutputObjectsDelegate` — used to scan the QR tags on plant
pots. It is the camera, in the ordinary sense.

**Following this recommendation would make iOS terminate the app** the first time
someone opened the plant scanner, which is exactly the failure mode
`Tools/validate_permissions.py` exists to prevent. That validator does not flag
the camera key, and it is right not to.

Worth noting because it is the mirror image of a finding the audit got right:
`NSPhotoLibraryUsageDescription` genuinely was unnecessary — `PhotosPicker` runs
out of process — and has been removed. One of the two was safe to act on; the
other was not, and they look identical from a distance.

### HP-3 — journal deletion does purge, and does take its attachments

The audit says private journal words "may remain in storage after the user
believes they were deleted" and asks for "a stated time limit for undo, followed
by permanent removal of the entry and its attachments."

All three of those already exist:

- `JournalEntry.restoreWindow` — thirty days.
- `SwiftDataWellnessRepository.purge(deletedBefore:)` destroys the rows, called
  from `ManageJournalEntry.purgeExpired()`.
- `SwiftDataMediaRepository.deleteOrphans()` runs immediately afterwards and
  removes the **file bytes** via `fileStore.delete(token:)`, not merely the
  database rows — including thumbnails, and including files with no record at
  all from an interrupted write.

Both run at launch, from `AppDependencies.performLaunchHousekeeping()`.

The salvageable part of the finding is the user-facing wording: nothing on the
journal screen tells the user that "delete" means thirty days of recoverability.
That is a real gap, and it is a copy change rather than the data-retention defect
the audit describes. Left for the same pass that adds erase-all, since the two
belong in one conversation with the user.

## Changed in this pass

Fixed, with the reasoning recorded at each site:

1. **Export no longer leaves personal data in `tmp`.** Each export wrote a fresh
   `SunnieExport-<uuid>` directory and forgot it. Now tracked and removed when
   the share sheet closes, and before a new export begins.
2. **Export failure is no longer silent.** `catch { exportedFiles = [] }` made a
   failed export indistinguishable from a broken button. It now raises a calm
   alert that states nothing was saved and nothing changed.
3. **Media files carry a protection class.**
   `.completeFileProtectionUntilFirstUserAuthentication` on write, and the same
   class on the containing directory. `UntilFirstUserAuthentication` rather than
   `Complete` deliberately: the stronger class makes files unreadable whenever
   the screen is locked, which would break launch housekeeping and background
   Watch delivery.
4. **The SwiftData store's protection is declared** in the entitlements
   placeholder as `com.apple.developer.default-data-protection`. That is the only
   mechanism that covers a SwiftData store, which cannot take a protection class
   through `ModelConfiguration`. It stays **inactive** with everything else in
   that file (ADR-012) — nothing was enabled.
5. **`NSPhotoLibraryUsageDescription` removed.**
6. **Stale test counts corrected** in four places the earlier pass missed —
   `README.md`, `DEVICE_BRING_UP.md`, and `COMPILE_RISK_REVIEW.md` twice.

## Deliberately not changed

**Erase-all (RB-4) was not built.** The audit is right that it is missing and
right that `PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` §74–77 promises "delete
individual record / delete category / delete all app data."

It was not attempted because it is a destructive, irreversible feature spanning
every repository, the media store, and Health, and **the app target cannot be
compiled here.** Writing an untested delete-everything path is how someone loses
their journal for real. This needs a compiler, a populated store to test against,
and a decision from the owner about what "erase" means for data already written
to Apple Health — which the app cannot reach back into.

**The 10+ `try? await …delete(…)` sites (HP-2) were not changed.** The finding is
correct, but the fix is a per-screen error-presentation pattern across nine
files, and none of it can be compiled or seen. It is mechanical work that belongs
with the first real build, not before it.

## Not verifiable here

Unchanged from before, and none of it moved in this pass: the app, Watch, and
widget targets have never been compiled; no screen has been rendered; no
migration has been run against a populated store; and ADR-017's schema namespace
freeze is still owed. The audit's ranking of migration as the highest-consequence
untested area matches this repository's own assessment.

## On the feature ideas

Reviewed and not started, which matches the audit's own instruction to leave them
until the blockers are closed. Two are worth flagging as unusually well-matched
to what already exists: the **"today is hard" switch** composes cleanly with the
existing quiet-hours and reminder-cadence machinery, and the **plant handover
card** is close to a presentation layer over `JungleExport`, which already builds
exactly that data. The **"why am I seeing this?" button** is the one with the
best ratio of trust gained to work required, since `ReminderPlanner` already
computes the reason and discards it.

The audit's "features to avoid" list matches the product's locked decisions —
no leaderboards, no tracking, no automatic health conclusions — and needs no
argument.
