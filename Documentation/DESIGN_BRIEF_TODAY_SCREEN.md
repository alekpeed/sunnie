# Design Brief — Today Screen

Written against the implemented screen, not a wish list. Every card, string, and
value below is in `Apps/iOS/Features/Today/`. If the design changes what's here,
that's fine — but it's a code change too, so worth knowing which is which.

## Before generating anything

Three rules from `CLAUDE.md` and the character bible that apply to mockups:

1. **Feed in the canonical references.** `Documentation/Reference_Images/Canonical/`
   is the visual source of truth for Sunnie. Generating him from a text
   description alone will produce a different sloth, and "do not silently invent
   a new Sunnie design" is a locked rule.
2. **Do not crop the mockup into production assets.** Mockups establish direction.
   Production art comes from the layered pipeline in
   `AssetsSource/ASSET_MANIFEST.md`.
3. **Ignore any text the generator renders.** It will be garbled or invented.
   Real copy lives in `Localizable.strings` and is tone-checked by tests.

## Card inventory, in order

The screen is a vertical scroll. Cards are 16pt apart with 16pt page margins.

| # | Card | Always shown? | Contents |
|---|---|---|---|
| 1 | Greeting | Yes | Sunnie at 132pt + his greeting line; branded day-cycle label beneath in small secondary text |
| 2 | Storage warning | Only on failure | Error card. Not part of the normal design |
| 3 | Your jungle | Yes | Section header + subtitle, one plant task row, primary action button, "See all N" if more |
| 4 | Wellness | Yes | Section header, affirmation line, two side-by-side secondary buttons |
| 5 | Sunnie's reaction | Only after logging care | Sunnie at 56pt + one warm line. Appears, then dismissed |
| 6–9 | Coming soon | Yes, for now | Travel, Meals, Daily puzzle, Collections — each a header + subtitle + "Coming soon" chip |

### 1. Greeting card

- Sunnie at **prominent** size (132pt), currently left of his text.
- Greeting text, e.g. *"Good morning, Vanessa. Let's keep today simple."*
- Below both: the branded label — **Sunnie Days**, **Sunnie Afternoonies**, or
  **Sunnie Nights** — in caption size, secondary colour. Those three strings are
  the only permitted day-cycle names.
- Sunnie's expression follows the time of day: waving in the morning, open-eyed
  by day, closed-eyed in the afternoon, calm in the evening, half-lidded at
  night, asleep late.

### 2. Your jungle card

- Header **"Your jungle"**, subtitle *"3 may be ready for a little attention"*.
- One task row: plant name (headline, rounded), care type beneath (*"Water"*) in
  secondary, and a status chip right-aligned.
- Status chip is icon + text, never colour alone: a drop icon with
  *"Waiting 2 days"* in the muted amber attention tone, or a clock with
  *"Today"* in neutral.
- Full-width primary button, sage green, *"Mark watered"* with a drop icon.
- If more than one task, a bordered secondary button *"See all 3"*.
- Two alternate states worth mocking: no plants at all (Sunnie at 88pt with a
  watering can, *"No plants yet"*), and nothing due (Sunnie at 56pt sitting,
  eyes closed, *"Nothing is waiting. Your jungle is looking cared for."*).

### 3. Wellness card

- Header **"Wellness"**. Subtitle appears only after a check-in:
  *"You checked in today."*
- An affirmation in body text: *"One little thing at a time is enough."*
- Two secondary buttons side by side: *"Check in"* (heart) and *"Write"* (pencil).

### 4–7. Coming soon cards

Travel, Meals, Daily puzzle, Collections. Header + one-line subtitle + a neutral
"Coming soon" chip. These disappear as phases land, so don't over-invest — but
they're on screen today and the design should account for four of them.

## Chrome

- **Navigation bar:** "Sunnie Days", inline (small, centred).
- **Tab bar, locked order:** Today (sun), Jungle (leaf), Travel (plane),
  Wellness (heart), More (grid). Selected tint is the sage plant green.

## Tokens

Palette below is the **Lush Tropical Jungle** theme in its day state — the
default. Two other themes ship (Travel Scrapbook, Day Cycle) and each has six
time-of-day variants, so treat these as one cell of a grid, not the whole design.

| Role | Hex | Used for |
|---|---|---|
| canvas | `#FFF8ED` | Page background |
| surface | `#FFF1DC` | Cards |
| surfaceRaised | `#FFFDF8` | Elevated controls |
| textPrimary | `#493528` | Main text |
| textSecondary | `#755E4D` | Subtitles, captions |
| accentPlant | `#A9C5A0` | Primary buttons, tab tint |
| accentSunnie | `#F6D47D` | Sunnie's halo, day accent |
| accentWarm | `#F3A58D` | Warm accent |
| accentCalm | `#B9A6E1` | Wellness, night |
| accentTravel | `#A8CBE4` | Travel |
| attention | `#D7A65A` | Waiting tasks. **Never red** |
| success | `#91B982` | Completion |
| error | `#C97972` | Genuine errors only |

- **Card radius:** 24pt continuous. **Buttons:** 16pt. **Chips:** capsule.
- **Spacing:** 8pt grid — 4, 8, 12, 16, 24, 32, 48.
- **Shadow:** very soft, 8pt blur, 2pt down, 6% black. Dark presentations drop
  shadow entirely and separate by tone.
- **Type:** system rounded semibold for headings, plain system for body,
  monospaced digits for counts. Everything scales with Dynamic Type.
- **Sunnie sizes:** 132 prominent / 88 medium / 56 small / 36 minimal.

## Non-negotiables

- Overdue plant care uses the muted amber attention tone. **Never red**, never an
  alarm, never a badge count that reads as debt.
- Colour is never the only carrier of state — every chip has an icon and a word.
- Night presentation must stay genuinely readable, not just dimmed.
- Sunnie frames the content; he never covers a control or pushes the first task
  below the fold.
- Nothing on this screen should imply the user is behind.
