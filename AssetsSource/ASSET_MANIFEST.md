# Asset Manifest

Records every production asset the app expects, and which are still placeholders.
`CLAUDE.md` requires a named placeholder rather than a silently invented Sunnie
design, so nothing here is guesswork about how he should look — the canonical
references in `Documentation/Reference_Images/Canonical/` are the only source of
truth for that.

## Current state

**No production Sunnie artwork exists.** `SunnieAvatarView` draws a circle with an
SF Symbol chosen from the semantic expression. It is a stand-in for layout and
accessibility only, and it is not a design proposal.

| Asset group | State | Used by |
|---|---|---|
| Sunnie base body layers | Placeholder | `SunnieAvatarView` |
| Sunnie face and eye variants | Placeholder | `SunnieAvatarView` |
| Sunnie mouth variants | Placeholder | `SunnieAvatarView` |
| Sunnie outfit overlays | Placeholder | Theme phase variants |
| Sunnie prop overlays | Placeholder | `SunnieVisualState.propID` |
| Theme backgrounds | Placeholder | `ResolvedTheme.backgroundAssetID` |
| App icon | Placeholder | `Assets.xcassets/AppIcon` |
| Collectible and reward art | Not started | Phase 8 |
| Travel stamps and postcards | Not started | Phase 5 |

## What the production art must supply

### Layered construction

Layered rather than flat, so simple motion is possible without a character rig
(`SUNNIE_CHARACTER_BIBLE.md` §12):

- Body base
- Face and eye variants
- Mouth variants
- Arm and hand overlays where a pose needs them
- Outfit overlays
- Handheld prop overlays
- Optional foreground and background layers

Transparent backgrounds, exported at @1x, @2x, and @3x. Source files stay in this
directory and never enter the runtime bundle; optimized runtime assets go in the
asset catalog.

### Naming

Asset names match the content IDs the code already uses, so dropping the art in
requires no code change:

```
sunnie.body.base
sunnie.face.{expression}          e.g. sunnie.face.happyOpenEyed
sunnie.pose.{pose}                e.g. sunnie.pose.holdingWateringCan
sunnie.outfit.{outfit}            e.g. sunnie.outfit.cozyPajamas
sunnie.prop.{prop}                e.g. sunnie.prop.wateringCan
sunnie.theme.{theme}.background.{phase}
```

The expression and pose segments are the raw values of `SunnieExpression` and
`SunniePose` in the shared package. Those enums are the complete required set.

### Expressions required for the 2D release

All fifteen from `SunnieExpression`: `happyOpenEyed`, `happyClosedEyed`,
`sleepyHalfLidded`, `sleeping`, `gentleWave`, `proud`, `curious`, `calmBreathing`,
`excitedDiscovery`, `huggingObject`, `thinking`, `traveling`, `caringForPlant`,
`celebratingQuietly`, `comforting`.

Note what is absent, and must stay absent: there is no angry, disappointed,
scolding, frightened, or distressed expression. Sunnie's register is consistently
positive; calm is allowed, negativity is not.

### Sizes

`SunniePresence` determines the rendered size, so each asset needs to read
clearly down to the smallest:

| Presence | Size | Where |
|---|---|---|
| `prominent` | 132pt | Today, Sunnie's Home |
| `medium` | 88pt | Feature landing screens, empty states |
| `small` | 56pt | Completion reactions |
| `minimal` | 36pt | Dense forms and lists |

## Visual QA checklist

Before approving any Sunnie asset, run `SUNNIE_CHARACTER_BIBLE.md` §14:

- Does he look as young as the canonical sheet?
- Is his head large and his face round?
- Are the eyes large and warm?
- Is the body compact?
- Does the outfit fit his proportions rather than changing them?
- Is he recognisable in silhouette?
- Is the expression kind?
- Does it work at its intended screen size?
- Is there a static equivalent if it animates?

## Reference images

`Documentation/Reference_Images/Canonical/` is the visual source of truth.

`Documentation/Reference_Images/Context/` shows useful settings and costumes, but
its taller, more realistic proportions are **not canonical**. Rebuild those
contexts with the young canonical Sunnie. Do not crop generated mockups into
production assets, and do not treat text inside any reference image as
authoritative copy.
