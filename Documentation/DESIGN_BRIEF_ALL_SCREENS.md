# Sunnie Days — Consolidated Design Brief

**All 25 screens, in one place, for the visual design pass.**

This is the document to work from when designing pages. It merges four sources
that currently live apart:

- `03_UX/SCREEN_SPECIFICATIONS.md` — what each screen must contain
- `03_UX/INFORMATION_ARCHITECTURE.md` — how screens connect
- `02_Character_and_Design/VISUAL_DESIGN_SYSTEM.md` — tokens, spacing, shapes
- `02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` — how each screen re-skins

…and adds two things the source documents don't have: **what is actually built
today**, and **an image-generation prompt per screen**.

Where this brief and a source document disagree, the source document wins and
this one is wrong — say so and it gets fixed.

---

## Contents

1. [How to use this](#1-how-to-use-this)
2. [Rules that apply to every screen](#2-rules-that-apply-to-every-screen)
3. [The design tokens](#3-the-design-tokens)
4. [Sunnie, in brief](#4-sunnie-in-brief)
5. [Screen index and build status](#5-screen-index-and-build-status)
6. [The screens](#6-the-screens) — S-01 … S-25
7. [The theme × time-of-day grid](#7-the-theme--time-of-day-grid)
8. [Prompt scaffolding](#8-prompt-scaffolding)

---

## 1. How to use this

Each screen entry has the same five parts:

| Part | What it's for |
|---|---|
| **Spec** | The required regions, verbatim from `SCREEN_SPECIFICATIONS.md` |
| **Built** | What exists in code right now, with the file path |
| **Design notes** | Density, hierarchy, Sunnie's role, what the screen must not imply |
| **States to mock** | Empty / loading / error / offline / denied, as applicable |
| **Prompt** | A ready-to-paste image-generation prompt |

Design against **Spec**, not against **Built** — the code is placeholder
presentation using native controls, and it's meant to be replaced. **Built** is
there so you know which screens will show your design immediately and which are
still stubs behind a "Coming soon" chip.

---

## 2. Rules that apply to every screen

These are locked in `CLAUDE.md` and the character bible. They are not style
preferences and a design that breaks one of them can't ship.

### Before generating anything

1. **Feed in the canonical references.**
   `Documentation/Reference_Images/Canonical/` is the visual source of truth for
   Sunnie — the character sheet, the sleep concept, and the wellness concept.
   Generating him from a text description alone produces a different sloth, and
   *"do not silently invent a new Sunnie design"* is a locked rule.
2. **Don't crop mockups into production assets.** Mockups establish direction.
   Production art comes from the layered pipeline in
   `AssetsSource/ASSET_MANIFEST.md`.
3. **Ignore any text the generator renders.** It will be garbled or invented.
   Real copy lives in `Apps/iOS/Resources/en.lproj/Localizable.strings` and is
   tone-checked by tests.

### The three day-cycle names

**Sunnie Days**, **Sunnie Afternoonies**, **Sunnie Nights**. These are the only
permitted public labels. Never "Sunnie Mornings" or "Sunnie Evenings" — not in a
mockup, not in a placeholder, not as a joke. The app title stays *Sunnie Days*
in every state.

Internally the engine has six phases (morning, day, afternoon, evening, night,
lateNight) which drive lighting and Sunnie's expression. Three names, six
lighting states.

### Tone, as it shows up visually

- **Overdue care is amber, never red.** No alarm colour, no badge count. A
  number on an icon reads as debt, which is exactly the framing that's ruled out.
- **Nothing may imply the user is behind.** No streak counters, no "you missed
  it", no progress bar that reads as a deficit.
- **Colour is never the only carrier of state.** Every status chip has an icon
  *and* a word.
- **Sunnie is never disappointed.** There is no scolding, frightened, or
  distressed expression in the library, and none should be designed.

### Accessibility, during the design, not after

- **Dynamic Type** — everything scales. Fixed-height cards with text in them
  will break; design them to grow.
- **Night presentations must be genuinely readable**, not the day design dimmed.
- **Reduce Motion** — every animation needs a static or crossfade-only fallback.
- **Contrast** — text on card must hold at large type sizes and in all three
  presentations.
- Every screen must define loading, empty, error, offline, denied-permission,
  Dynamic Type, VoiceOver, and reduced-motion behaviour.

---

## 3. The design tokens

Provisional values from `VISUAL_DESIGN_SYSTEM.md` §3. Tunable after contrast
testing; the *names* are not, because themes swap values behind them.

| Token | Hex | Use |
|---|---|---|
| `canvasWarm` | `#FFF8ED` | Default background |
| `surfaceCream` | `#FFF1DC` | Cards and sheets |
| `surfaceRaised` | `#FFFDF8` | Elevated controls |
| `textPrimary` | `#493528` | Main text |
| `textSecondary` | `#755E4D` | Secondary text |
| `peach` | `#F3A58D` | Warm accent, wellness |
| `butter` | `#F6D47D` | Sunnie / day accent |
| `lavender` | `#B9A6E1` | Calm / night accent |
| `sage` | `#A9C5A0` | Plant accent |
| `sky` | `#A8CBE4` | Travel accent |
| `successSoft` | `#91B982` | Completion without alarm |
| `warningSoft` | `#D7A65A` | Non-critical attention |
| `errorSoft` | `#C97972` | Genuine errors only |

**Spacing** — 8pt base grid, 4pt exceptions: 4 / 8 / 12 / 16 / 24 / 32 / 48.

**Shapes** — cards 20–28pt continuous radius (24 in code); chips capsule;
buttons 14–20pt or capsule; images rounded rectangles or soft cutout art.

**Shadows** — low opacity, small blur, warm. Night presentations drop shadow and
separate by tone instead. Never rely on shadow alone to show interactivity.

**Type** — system rounded for headings, plain system for body, monospaced digits
for counts and timers. No all-caps paragraphs. Decorative script only in static
artwork, never in essential UI text.

**Sunnie sizes** — 132pt prominent / 88 medium / 56 small / 36 minimal.

**Density by area** (§12): Today medium with progressive disclosure; Jungle list
higher with filters and bulk actions; Travel context-dependent and can be
visually rich; Wellness lower and calmer; Games per-mechanic; Settings standard
native clarity.

---

## 4. Sunnie, in brief

Full detail in `SUNNIE_CHARACTER_BIBLE.md`. The parts that constrain a mockup:

- **Young, baby-faced, plush-toy cute male sloth.** Never tall, mature,
  realistic, lanky, or adult-proportioned.
- Head is **42–48% of standing height**, wider than the torso. Short compact
  body, short plush limbs, small rounded claws, oversized eyes.
- Large glossy dark-brown eyes with warm highlights, cream face mask, soft brown
  eye patches, small dark nose, small smiling mouth, peach-pink blush, short
  eyebrows, small hair tuft.
- **Never:** eye bags, wrinkles, narrow eyes, long muzzle, adult jawline,
  realistic teeth, angry brows.
- Fur light caramel/tan; face creamy ivory; plush or quilted texture, not
  wildlife-photo hair detail.
- Default wardrobe: butter-yellow quilted pyjamas or sweater with a small sun
  emblem; nightcap when sleeping; lavender blanket; warm mug for calm scenes.

**Emotional register is consistently positive.** Calm is allowed. Negative is
not.

---

## 5. Screen index and build status

| ID | Screen | Tab | Built today | Phase |
|---|---|---|---|---|
| S-01 | Today | Today | **Yes** — full card stack | 1–3 |
| S-02 | Jungle dashboard | Jungle | **Yes** — sections, due/upcoming, quick care | 2 |
| S-03 | Plant collection | Jungle | Partial — list only, no filters/sort/bulk | 4 |
| S-04 | Plant detail | Jungle | **Yes** — schedules, history, quick care | 2 |
| S-05 | Plant editor | Jungle | No | 4 |
| S-06 | Travel dashboard | Travel | No — placeholder | 5 |
| S-07 | Trip overview | Travel | No | 5 |
| S-08 | Packing | Travel | No | 5 |
| S-09 | World map | Travel | No | 5 |
| S-10 | Wellness dashboard | Wellness | **Yes** | 3 |
| S-11 | Check-in | Wellness | **Yes** — incl. photo/voice note | 3 |
| S-12 | Calm player | Wellness | **Yes** — breathing, meditation, sounds | 3 |
| S-13 | Journal home | More | **Yes** — entries, drafts, search, undo | 3 |
| S-14 | Journal editor | More | **Yes** — autosave, gratitude, attachments | 3 |
| S-15 | Meals dashboard | More | No — placeholder | 6 |
| S-16 | Meal planner | More | No | 6 |
| S-17 | Grocery list | More | No | 6 |
| S-18 | Games home | More | No — placeholder | 7 |
| S-19 | Game session | More | No | 7 |
| S-20 | Game result | More | No | 7 |
| S-21 | Collections | More | No — placeholder | 8 |
| S-22 | Sunnie Home | More | No — placeholder | 8 |
| S-23 | Theme gallery | More | **Yes** — three themes, phase preview | 2 |
| S-24 | Settings | More | **Yes** — day cycle, audio, a11y, reminders | 1–3 |
| S-25 | Permission explainer | — | Partial — inline in Settings | 9 |

**Eleven of 25 exist and will render your design immediately.** The rest are
behind "Coming soon" chips, so designs for them can be built ahead of the code.

### Navigation

Five tabs, **order locked**: Today (sun) · Jungle (leaf) · Travel (plane) ·
Wellness (heart) · More (grid). Selected tint is sage.

Each tab keeps its own navigation stack across tab switches. Sheets are for
short creation, confirmation, quick logging, and filters; navigation
destinations are for deep records and multi-step workflows.

Deep links resolve into typed routes:
`sunniedays://today` · `jungle/due` · `plant/{uuid}` · `trip/{uuid}` ·
`wellness/checkin` · `games/daily` · `journal/new`

---

## 6. The screens

---

### S-01 · Today

The daily operational centre.

**Spec — required regions:** day presentation header · Sunnie and greeting ·
affirmation · travel card · jungle card · wellness card · meal/prep card · daily
puzzle card · progress/collection card · quick actions.

**Spec — primary actions:** open current trip · complete plant task · check in ·
open meal plan · play daily puzzle · visit Sunnie Home.

**Built** (`Apps/iOS/Features/Today/`): vertical scroll, cards 16pt apart, 16pt
page margins.

| # | Card | Always? | Contents |
|---|---|---|---|
| 1 | Greeting | Yes | Sunnie at 132pt + greeting; branded day-cycle label beneath in caption/secondary |
| 2 | Storage warning | On failure only | Error card, not part of the normal design |
| 3 | Your jungle | Yes | Header + subtitle, one plant task row, primary action, "See all N" |
| 4 | Wellness | Yes | Header, affirmation line, two side-by-side secondary buttons |
| 5 | Sunnie's reaction | After logging care | Sunnie at 56pt + one warm line, dismissible |
| 6–9 | Coming soon | For now | Travel, Meals, Daily puzzle, Collections — header + subtitle + chip |

**Design notes**

- Sunnie frames content; he never covers a control or pushes the first task
  below the fold.
- The jungle task row's status chip is icon + text: a drop with *"Waiting 2
  days"* in muted amber, or a clock with *"Today"* in neutral.
- Sunnie's expression follows the phase — waving in the morning, open-eyed by
  day, closed-eyed in the afternoon, calm in the evening, half-lidded at night,
  asleep late.
- Cards may collapse after completion but must stay reviewable.
- The four "Coming soon" cards disappear as phases land, so don't over-invest —
  but four of them are on screen today.

**States to mock:** no plants at all (Sunnie 88pt with a watering can, *"No
plants yet"*) · nothing due (Sunnie 56pt sitting, eyes closed, *"Nothing is
waiting. Your jungle is looking cared for."*) · loading · storage-failure banner
· offline.

**Prompt**

> A warm, illustrated iPhone app home screen for a cosy plant-and-wellness
> companion app. Vertical scroll of soft cream cards (`#FFF1DC`) on a warm ivory
> background (`#FFF8ED`), 24pt continuous rounded corners, very soft warm
> shadows. Top card: a small plush baby-faced cartoon sloth — light caramel fur,
> creamy ivory face mask, oversized glossy dark-brown eyes with warm highlights,
> peach-pink cheek blush, butter-yellow quilted pyjamas with a small sun emblem
> — sitting to the left of a friendly greeting line, with a small secondary-text
> label beneath. Below: a plant-care card with one task row and a full-width
> sage-green (`#A9C5A0`) rounded button; a wellness card with an affirmation
> line and two smaller lavender-accented buttons; then four quieter cards each
> with a small capsule chip. Bottom: a five-item native iOS tab bar with sage
> tint. Soft storybook illustration style, rounded system-style typography,
> generous 16pt spacing, adult-appropriate and calm — not a children's game.
> Warm morning light.

---

### S-02 · Jungle dashboard

**Spec — required regions:** due today · overdue · needs attention · upcoming ·
travel coverage · search/filter controls · recent care · collection summary.

**Spec — primary actions:** add plant · start care session · open plant · create
travel plan.

**Built** (`Apps/iOS/Features/Jungle/Screens/JungleScreen.swift`): sectioned
list — due today, upcoming, waiting, full collection. Quick-care sheet from a
row. No search, filters, travel coverage, or collection statistics yet (Phase 4).

**Design notes**

- Higher information density than Today — this is a working list.
- **"Overdue" is a spec word, not a UI word.** In code the section is *waiting*,
  and the chip reads *"Waiting 2 days"* in muted amber. Keep that framing:
  the plant is waiting, the user is not failing.
- Travel coverage appears here as a status, not a warning — a plant covered by a
  caretaker while the user is away is fine, and should look fine.
- Recent care is a reassurance region, not an audit trail.

**States to mock:** no plants · nothing due (everything cared for) · loading ·
error · a long list needing filters.

**Prompt**

> An illustrated iPhone plant-care dashboard. Sectioned list on warm ivory
> (`#FFF8ED`) with cream card groups (`#FFF1DC`), 24pt rounded corners. Section
> headers in rounded semibold brown (`#493528`): "Due today", "Coming up",
> "Waiting". Each row: plant name, care type beneath in muted brown, and a
> right-aligned capsule chip with a small icon and a word — a water drop with
> "Waiting 2 days" in soft amber (`#D7A65A`), a clock with "Today" in neutral.
> Small illustrated plant thumbnails in soft rounded squares. A search field at
> the top. Bottom-right, a small plush baby-faced cartoon sloth in green
> gardening overalls with a tiny watering can, peeking beside the list without
> covering it. Soft storybook illustration, calm and organised, no red, no alarm
> colours, no badge counts.

---

### S-03 · Plant collection

**Spec:** grid/list toggle · search · filter by room, species, status, care
type, caretaker, travel risk · sort by name, next due, last care, acquired date
· multi-select for bulk care · persistent filter state.

**Built:** a plain list section inside the Jungle dashboard. Everything above is
Phase 4.

**Design notes**

- This is the densest screen in the app. Grid mode is photo-led; list mode is
  status-led.
- Filter state persists across tab switches — the design needs a visible,
  dismissible indication of *which* filters are on, or a user will wonder where
  their plants went.
- Multi-select needs a selection mode that doesn't fight the row tap.
- Bulk care is a genuinely useful action ("water these six") and should feel
  generous, not administrative.

**States to mock:** grid · list · filters applied (with the indicator) · empty
result from a filter (never a dead end — offer to clear it) · selection mode
with a count.

**Prompt**

> An illustrated iPhone plant collection screen in grid mode. Warm ivory
> background (`#FFF8ED`), two-column grid of cream cards (`#FFF1DC`) with 20pt
> rounded corners, each showing a soft illustrated houseplant photo, the plant's
> name in rounded semibold warm brown, and a small status chip. Above the grid:
> a search field and a horizontal row of small capsule filter chips, two of them
> filled in sage green to show they're active. Top-right: a grid/list toggle.
> Soft storybook illustration style, dense but calm, generous 8pt spacing, warm
> soft shadows, no harsh borders.

---

### S-04 · Plant detail

**Spec:** hero photo · name/nickname/species · status and next due · quick-care
buttons · schedule · history · health · growth photos ·
location/light/soil/pot · notes · travel coverage · QR identity · edit.

**Built** (`PlantDetailScreen.swift`): name, status, quick care, schedules,
care history. No hero photo, health, growth timeline, QR, or edit yet.

**Design notes**

- The hero photo is the emotional anchor. This is the one screen where a big
  image earns its space.
- Quick-care buttons are the most-used control in the app — big, thumb-reachable,
  unambiguous, one tap.
- History is a record of care given, not a compliance chart. No streaks.
- Growth photos are the reward: a timeline that shows the plant getting bigger
  is the payoff for months of watering.
- QR identity is a small utility, not a feature to celebrate — it lives near
  Edit, not near the hero.

**States to mock:** no photo yet · no schedule set · long history · a plant
under travel coverage.

**Prompt**

> An illustrated iPhone plant detail screen. Top third: a large soft-edged
> illustrated photo of a monstera in a terracotta pot, rounded 24pt corners.
> Below on warm ivory (`#FFF8ED`): the plant's name in large rounded semibold
> warm brown (`#493528`), species beneath in muted brown, and a small capsule
> chip reading "Watered 3 days ago" in soft sage. Then a row of three large
> rounded quick-action buttons with simple icons — a water drop, a leaf, a sun —
> in sage green (`#A9C5A0`), pale peach, and butter yellow. Below: a cream card
> listing a care schedule, and a second card with a short history list. Soft
> storybook illustration style, warm and generous, no red, no alarm colours.

---

### S-05 · Plant editor

**Spec:** sections with progressive disclosure. Species lookup is optional;
manual entry always works. **Never block saving because reference content is
missing.**

**Built:** nothing. Phase 4.

**Design notes**

- The one hard rule is the last line of the spec: a missing species, a failed
  lookup, or an absent photo must never prevent saving. Design the save button
  as always-enabled once there's a name.
- Progressive disclosure means: name and room visible; light, soil, pot,
  acquisition, notes collapsed behind clearly labelled sections.
- Species lookup should look like an offer, not a required field.

**States to mock:** new plant (mostly collapsed) · editing an existing one ·
lookup unavailable/offline · validation (only "needs a name").

**Prompt**

> An illustrated iPhone form screen for adding a plant. Warm ivory background
> (`#FFF8ED`), native-style grouped form sections on cream cards (`#FFF1DC`)
> with 20pt rounded corners. First section: a large rounded photo-add tile with
> a soft dashed border and a small camera icon, then a text field for the plant's
> name and a room picker. Below, three collapsed section headers with disclosure
> chevrons, labelled in rounded semibold warm brown. Top-right, a "Save" button
> in sage green, clearly enabled. A small plush baby-faced cartoon sloth in green
> gardening overalls sits in the bottom corner holding a tiny empty pot,
> encouraging and not blocking anything. Soft storybook illustration, calm,
> native iOS form conventions.

---

### S-06 · Travel dashboard

**Spec:** active trip · upcoming trips · work travel shortcut · world map ·
recent memories · saved places · passport summary · create trip.

**Built:** placeholder screen. Phase 5.

**Design notes**

- This is where the **Travel Scrapbook** theme has the most to say: cream paper,
  taped photos, stamps, map fragments, postcards, soft blue and coral accents.
- Vanessa is a flight attendant, so *work travel* is a first-class shortcut, not
  an afterthought — and work trips should feel routine and quick to set up, not
  ceremonial.
- The passport summary and recent memories are the warm half; active trip and
  upcoming are the operational half. Don't let the decorative half crowd the
  operational one.
- Sunnie's flight-attendant outfit belongs here: navy tailored jacket simplified
  for a small plush body, white shirt, red tie, small name badge, small roller
  bag. Rebuilt on the canonical young proportions — **never** the tall adult
  body from the context reference.

**States to mock:** no trips ever · a trip in progress · a trip tomorrow ·
returning today · offline (cached places, no map imagery promised).

**Prompt**

> An illustrated iPhone travel dashboard styled as a warm scrapbook. Cream paper
> background with subtle texture, elements arranged like taped-in photos and
> postcards with soft drop shadows and small illustrated stamps in the corners.
> Top: a wide "active trip" card with a destination name, dates, and a soft blue
> (`#A8CBE4`) accent bar. Below: a row of two smaller upcoming-trip cards, a
> compact rounded world-map fragment with small pin markers, and a strip of three
> square memory photos with tape corners. A small plush baby-faced cartoon sloth
> — light caramel fur, oversized glossy dark eyes, wearing a simplified navy
> flight-attendant jacket with a red tie and a tiny name badge, pulling a small
> roller bag — stands at the lower left. Soft storybook illustration, coral and
> soft-blue accents on cream, warm and organised.

---

### S-07 · Trip overview

**Spec:** dates/status · destination/local and home time · weather summary ·
checklist progress · packing progress · plant coverage status · meal prep
status · itinerary · notes.

**Built:** nothing. Phase 5.

**Design notes**

- **Two clocks side by side** — destination and home — is the signature element.
  Get that right and the screen works.
- Four progress readouts (checklist, packing, plants, meals) need one consistent
  treatment. Progress here is informational, not a score: "6 of 10 packed" with
  no judgement about the other four.
- Weather is a summary, not a forecast app. One line and an icon.
- Plant coverage status is the reassurance that the jungle is fine while away.

**States to mock:** trip not started · in progress · returning today · weather
unavailable · no itinerary added.

**Prompt**

> An illustrated iPhone trip overview screen on cream scrapbook paper. Top: a
> destination name in large rounded semibold, dates beneath, and two side-by-side
> circular clock faces labelled with city names — one soft blue, one warm peach —
> showing different times. Below: a compact weather line with a small illustrated
> sun-and-cloud icon. Then a 2×2 grid of small cream cards, each with a label and
> a soft rounded progress bar in a different muted accent — soft blue, coral,
> sage green, butter yellow. Bottom: a short itinerary list with small time
> stamps. Taped-photo and stamp decoration at the edges. Soft storybook
> illustration, calm and legible, progress shown without any sense of pressure.

---

### S-08 · Packing

**Spec:** template selection · categories · required/optional · quantity ·
packed state · search/add custom item · reuse template · **separate
work/personal/food sections.**

**Built:** nothing. Phase 5.

**Design notes**

- Checklists invite guilt-inducing design. Resist it: unpacked items are not
  failures, and there is no "you've only packed 40%" framing.
- Required vs optional needs a visual distinction that doesn't read as
  pass/fail — a soft label, not a red asterisk.
- The work/personal/food split is a real operational need for a flight
  attendant. Three clear sections, not a filter.
- Templates are the time-saver. "Reuse last trip's list" should be one tap and
  prominent.

**States to mock:** fresh from a template · half packed · all packed (a warm,
quiet acknowledgement — not confetti) · custom item being added · empty.

**Prompt**

> An illustrated iPhone packing checklist. Cream paper background, three clearly
> separated sections with rounded semibold headers — "Work", "Personal", "Food".
> Each row: a soft rounded checkbox (some ticked in sage green with a gentle
> check, some empty), the item name, a small quantity stepper on the right, and
> an occasional small muted "optional" capsule label. At the top, a wide button
> reading "Use last trip's list" in soft blue (`#A8CBE4`), and a search field.
> A small plush baby-faced cartoon sloth in a simplified navy flight-attendant
> jacket sits beside a small open suitcase in the corner. Soft storybook
> illustration, calm, nothing red, no percentage badges.

---

### S-09 · World map

**Spec:** MapKit map · visited/saved place annotations · filters · **list
fallback** · **offline state showing cached place records without promising map
imagery** · add past trip/place.

**Built:** nothing. Phase 5.

**Design notes**

- The offline rule is the design constraint: when map tiles aren't available,
  the screen must still be useful and must not show an empty grey rectangle that
  looks broken. Design the offline state as a *list of places*, presented
  deliberately — not as a degraded map.
- Annotations are illustrated pins/stamps, not default MapKit markers.
- Visited vs saved needs two distinguishable pin treatments that survive being
  small and overlapping.
- "Add a past trip" is important: the map is a memory object, and Vanessa has
  years of flights that predate the app.

**States to mock:** map with pins · map offline (list fallback) · no places yet
· filters applied · a cluster of pins in one region.

**Prompt**

> An illustrated iPhone world map screen. A soft, warm-toned stylised world map
> filling most of the screen — muted sage landmasses on pale cream ocean, no
> harsh political borders — with a dozen small illustrated pin markers: some as
> little coral postage stamps for visited places, some as soft outlined pins for
> saved ones. A floating cream card at the bottom shows one selected place with
> its name, a date, and a tiny photo. A small row of capsule filter chips floats
> at the top. Soft storybook illustration in a travel-scrapbook style, warm and
> inviting, legible at small pin sizes.

---

### S-10 · Wellness dashboard

**Spec:** check-in status · affirmation · recommended calm tool · breathing ·
meditation · sounds · journal · trends.

**Built** (`Features/Wellness/Screens/WellnessScreen.swift`): check-in status
and entry point, affirmation, one suggested practice, breathing and meditation
lists, calm sounds, journal shortcut, history summary. Sunnie's acknowledgement
card appears after a check-in with at most one optional next step.

**Design notes**

- **Lowest density in the app.** More whitespace, slower pacing, larger touch
  targets. This screen should feel like exhaling.
- Lavender (`#B9A6E1`) leads here rather than sage.
- The suggestion after a check-in is *at most one* and always dismissible
  immediately. It must never look like an instruction.
- Trends describe what was recorded. **No causal or diagnostic claim** — not in
  a chart title, not in an axis label, not in a summary line.
- Sunnie's calm poses belong here: meditating, holding a mug, breathing.

**States to mock:** not checked in today · checked in · Sunnie's acknowledgement
card showing · no history yet · a month of history.

**Prompt**

> An illustrated iPhone wellness screen, calm and spacious. Warm ivory background
> (`#FFF8ED`) with generous empty space between soft cream cards. Top: a small
> plush baby-faced cartoon sloth — light caramel fur, creamy face mask, oversized
> gentle half-closed eyes, peach blush — sitting cross-legged in a meditation
> pose with a soft lavender blanket, beside a short affirmation line in warm
> brown. Below: a wide rounded "Check in" card with a lavender (`#B9A6E1`)
> accent; then three quiet cards for breathing, a meditation, and calm sounds,
> each with a small soft icon. At the bottom, a low-contrast card showing a
> simple, unlabelled soft bar pattern. Soft storybook illustration, unhurried,
> lots of breathing room, nothing clinical.

---

### S-11 · Check-in

**Spec:** mood first · optional energy, stress, sleep · note/voice/photo · save
· skip optional fields · **no "bad answer" state.**

**Built** (`CheckInSheet` in `WellnessScreen.swift`): a sheet with four scales,
each defaulting to unanswered, an optional note, and photo + voice-note
attachment. A check-in with only a voice note is a valid entry.

**Design notes**

- **"No answer" is a real, selectable option**, not the absence of interaction.
  Leaving a question blank must not require avoiding the control.
- Scales use **labelled words, not faces**. Face scales imply a correct answer
  and don't survive VoiceOver.
- No scale value may be styled as bad. A low mood and a high mood get the same
  visual weight — no red end, no frowning icon, no warning tint.
- Mood first, everything else visibly optional.
- Attachments are offered, never prompted. An entry without one is complete.

**States to mock:** untouched (all unanswered) · partly filled · with a voice
note recording in progress · with a photo attached · microphone denied.

**Prompt**

> An illustrated iPhone check-in sheet, presented as a warm modal over a dimmed
> background. Cream sheet (`#FFF1DC`) with a rounded top edge. First section:
> "Mood" as a rounded semibold header with a horizontal row of five equally
> weighted, identically styled capsule options labelled with words, one softly
> highlighted in lavender — none coloured red or green, none larger than the
> others. Below, three more collapsed-looking optional sections, and a multiline
> note field with placeholder text. At the bottom, two small soft buttons with a
> camera icon and a microphone icon. A small plush baby-faced cartoon sloth with
> gentle open eyes sits at the top corner of the sheet. Soft storybook
> illustration, calm, entirely non-judgemental — no faces, no emoji scale, no
> good/bad colour coding.

---

### S-12 · Calm player

**Spec:** practice name · duration · progress · pause/resume/stop · music and
ambience · captions/instructions · interruption recovery · **HealthKit write
status only after completion.**

**Built** (`Features/Wellness/Screens/PracticeScreens.swift`): breathing player
with a phase-driven animation, meditation player, and calm sound library with a
sleep timer (fades rather than stops) and favourites. Audio handles
interruptions — a call pauses and resumes; headphones out stops rather than
switching to speaker. No audio assets ship yet.

**Design notes**

- The breathing animation *is* the screen. Everything else recedes.
- **Reduce Motion is not optional here** — the breathing guide needs a
  non-animated form (a changing text instruction with a slow crossfade) that
  works just as well.
- Captions/instructions must be readable, because someone with their eyes half
  closed is the target user.
- The sleep timer fades rather than cuts: the whole point is that someone is
  falling asleep, and a hard stop would wake them. "Keep playing" is the default
  and a real choice, not an off switch.
- Nothing auto-plays on opening the sound library.

**States to mock:** breathing mid-inhale · breathing under Reduce Motion ·
meditation playing · sound library with favourites · sleep timer set · resumed
after an interruption.

**Prompt**

> An illustrated iPhone breathing exercise screen, very dark and calm for
> night-time use. Deep warm charcoal-brown background with a soft lavender glow.
> Centre: a large soft-edged circle, gently luminous in pale lavender
> (`#B9A6E1`), sized as if mid-expansion. Above it, a single short instruction
> word in large light rounded type. Beneath, a slim unobtrusive progress line and
> three minimal rounded controls — pause, stop, sound. In the lower corner, a
> small plush baby-faced cartoon sloth curled up asleep with a tiny nightcap and
> a lavender blanket, softly lit. Almost no other UI. Soft storybook
> illustration, high contrast text on dark, genuinely comfortable in a dark room.

---

### S-13 · Journal home

**Spec:** new entry · drafts · recent entries · calendar · search · tags ·
favorites.

**Built** (`Features/Journal/Screens/JournalScreens.swift`): entries, drafts
section, search, reversible delete with an undo affordance. Calendar, tags, and
favourites are later.

**Design notes**

- Drafts get their own section with a plain reassurance: they save as you go,
  and closing loses nothing.
- Deletion is reversible for thirty days. The undo affordance should be calm and
  present, not a panicky red toast.
- Entries are memory objects — a scrapbook, not a database table. Room for a
  date, a first line, and eventually a photo thumbnail.
- The empty state is specified in the design system: a blank scrapbook with a
  clear "New entry" action.

**States to mock:** empty · with drafts · search with results · search with no
results · just-deleted with undo showing.

**Prompt**

> An illustrated iPhone journal list screen styled as a soft scrapbook. Warm
> cream paper background, a search field at the top, then a small section headed
> "Unfinished" containing one entry card with a muted "Draft" capsule chip. Below,
> a section of entry cards, each with a first-line preview in warm brown, a small
> date beneath in muted brown, and some with a tiny taped photo thumbnail in the
> corner. Top-right, a rounded compose button with a pencil icon. Soft storybook
> illustration, paper texture, warm and personal, calm and uncluttered.

---

### S-14 · Journal editor

**Spec:** autosaved draft · text · voice note · photos · gratitude items ·
mood/trip/plant links · tags · save/delete draft.

**Built:** title, body, gratitude items, photo and voice-note attachment,
autosave every few seconds and again on dismiss. The dismiss button says
**"Close"**, not "Cancel" — the draft is already saved, and the label must not
imply otherwise. Links and tags are later.

**Design notes**

- The writing area is the screen. Everything else is a secondary section beneath
  it.
- Autosave should be quietly visible — a small, unanxious indication that work is
  safe. Not a spinner, not a "saving…" that flickers.
- Gratitude items are a small, warm list, not a required section.
- Attachments are optional and removable; the footer says so plainly, so an
  entry without one never reads as unfinished.

**States to mock:** empty new draft · mid-writing · with a photo and a voice
note attached · recording in progress · resumed draft.

**Prompt**

> An illustrated iPhone journal writing screen. Warm cream paper background
> filling most of the screen with a large multiline text area, a light title
> field above it, and soft handwriting-lined paper texture behind the text. Below
> the writing area: a small section headed "Glad about" with two short list
> items and a plus button, then a row of two soft buttons with a camera icon and
> a microphone icon, and one attached item shown as a small rounded thumbnail with
> a remove ✕. Top-left a "Close" button, top-right "Done". Soft storybook
> illustration, paper texture, generous and inviting to write in, no clutter
> around the text.

---

### S-15 · Meals dashboard

**Spec:** today's plan · travel context · prep tasks · packed food · grocery
list · pantry/use-before-trip · suggestions.

**Built:** placeholder. Phase 6.

**Design notes**

- **Vanessa's locked dietary rule is no eggs.** Any suggestion surface must
  respect it, and the design should have a clear, quiet way to show that a
  suggestion has been filtered — without turning it into a restriction banner.
- "Use before trip" is the genuinely useful bit for someone who flies: food that
  will spoil while away. Give it real space.
- Packed food connects to Travel. Show the link, don't duplicate the screen.
- Suggestions are offers. Never a plan the user has to decline.

**States to mock:** no plan today · plan ready · prep tasks pending · travel
context active (trip in two days) · empty pantry.

**Prompt**

> An illustrated iPhone meal planning dashboard. Warm ivory background with cream
> cards. Top card: "Today" with three small meal rows, each with a soft
> illustrated food icon and a short dish name. Below: a card headed "Use before
> you go" with two items and small date labels in soft amber; a prep-task card
> with two rounded checkboxes; and a compact grocery-list card showing a count.
> A small plush baby-faced cartoon sloth in a soft apron holds a small bowl in
> the corner. Soft storybook illustration, warm peach and butter-yellow accents,
> appetising and calm, nothing clinical or diet-focused.

---

### S-16 · Meal planner

**Spec:** day/context selector · meal slots · recipe/custom meal · prep date ·
pack/refrigerate flags · grocery impact.

**Built:** nothing. Phase 6.

**Design notes**

- Meal slots across days is a grid problem. It must survive Dynamic Type, which
  a naive week-grid will not — plan for a per-day column that scrolls.
- "Grocery impact" is the clever part: adding a meal shows what it adds to the
  list. Make that feedback immediate and small.
- Pack/refrigerate flags are for flight days. Small icons, clearly labelled.
- Custom meals must be as easy as recipes. Most real meals aren't in a database.

**States to mock:** empty week · partly planned · a day with a trip on it · a
meal being added with grocery impact showing.

**Prompt**

> An illustrated iPhone meal planner. Warm ivory background. A horizontal row of
> seven small day chips at the top, one selected in soft peach. Below, a vertical
> stack of cream meal-slot cards labelled breakfast, lunch, dinner, snack — two
> filled with a dish name and a small illustrated food icon, two showing a soft
> dashed "add" outline. Each filled card has two tiny icon flags in the corner, a
> small suitcase and a snowflake. At the bottom, a compact strip showing "adds 4
> items to your list" in muted brown. Soft storybook illustration, warm, calm,
> clear structure.

---

### S-17 · Grocery list

**Spec:** group by category · linked meals · quantity · purchased state · add
custom item · pantry transfer.

**Built:** nothing. Phase 6.

**Design notes**

- This is used one-handed in a shop. Big rows, big tap targets, high contrast,
  and it must work with a phone held at arm's length.
- Purchased items should move or fade rather than vanish — a shopper needs to
  see what they've already got.
- "Linked meals" answers *why is this on my list* — a small caption, not a
  separate screen.
- Pantry transfer is the completion action: bought → in the pantry.

**States to mock:** full list by category · half purchased · all purchased ·
custom item being added · empty.

**Prompt**

> An illustrated iPhone grocery list, designed for one-handed use in a shop.
> Warm ivory background, large comfortable rows grouped under rounded semibold
> category headers — "Produce", "Dairy", "Pantry". Each row: a large soft rounded
> checkbox, the item name in generous readable warm brown type, a quantity on the
> right, and a tiny muted caption beneath naming the meal it's for. Two rows are
> ticked in sage green and softly faded rather than removed. A wide "Add item"
> button at the bottom. Soft storybook illustration, high contrast, large touch
> targets, uncluttered.

---

### S-18 · Games home

**Spec:** daily puzzle · continue · categories · featured games · rewards ·
recent results.

**Built:** placeholder. Phase 7.

**Design notes**

- The daily puzzle is the hero and the Today-screen hook.
- **No streak language anywhere.** Missing yesterday's puzzle costs nothing and
  must not be visible. "Recent results" is a record, not a run.
- Rewards connect to Collections — show what a game unlocks, since that's the
  motivation.
- Keep it playful without becoming a children's game; the visual direction is a
  polished illustrated companion app.

**States to mock:** puzzle unstarted · in progress ("Continue") · completed
today · no games played yet.

**Prompt**

> An illustrated iPhone games home screen. Warm ivory background. A large hero
> card at the top in butter yellow (`#F6D47D`) with a soft illustrated puzzle
> motif, a short title, and a rounded "Play" button — a small plush baby-faced
> cartoon sloth peeks over its lower edge with a delighted expression. Below: a
> horizontal row of three smaller square game cards with distinct soft
> illustrated icons, then a compact rewards strip showing three small collectible
> items, one of them softly greyed. Soft storybook illustration, playful but
> grown-up, warm palette, no scores or streak counters anywhere.

---

### S-19 · Game session

**Spec:** game-specific layout inside a common host with exit/save · rules/help
· hint · audio/haptics · progress · **accessibility alternative.**

**Built:** nothing. Phase 7.

**Design notes**

- Design the **host chrome**, not a game. The chrome has to work around any
  mechanic: a consistent place for exit, help, hint, and progress that never
  overlaps the play area.
- Exit always saves. Leaving mid-game must be safe and obviously safe.
- Hint is generous and unpenalised — no "using a hint reduces your score".
- The accessibility alternative is a spec requirement, not a nicety: every game
  needs a way to play that doesn't depend on its primary interaction (timing,
  dragging, colour).

**States to mock:** chrome around a generic play area · help sheet open · hint
shown · paused/exiting.

**Prompt**

> An illustrated iPhone game screen showing the surrounding interface chrome
> around a soft empty play area. Warm ivory background; the central play region
> is a large cream rounded rectangle with a very soft inner shadow. Top-left, a
> small rounded exit button; top-right, small help and sound buttons. Along the
> bottom, a slim soft progress indicator and a rounded "Hint" button in pale
> peach. The chrome is minimal and sits clear of the play area on all sides. A
> small plush baby-faced cartoon sloth watches from the bottom-right corner,
> curious and encouraging. Soft storybook illustration, uncluttered, everything
> at the edges.

---

### S-20 · Game result

**Spec:** result/score · **clear explanation** · reward progress · Sunnie
reaction · replay or next action.

**Built:** nothing. Phase 7.

**Design notes**

- "Clear explanation" is the spec's own emphasis: the player should understand
  *why* they got the result, especially when they got it wrong. Explanation
  above celebration.
- Sunnie's reaction is warm regardless of outcome. There is no disappointed
  expression in the library, and a loss should feel like company, not judgement.
- Reward progress shows what moved, not what's still missing.
- Replay is offered, never pushed.

**States to mock:** solved · not solved · reward unlocked · reward progressed
but not unlocked.

**Prompt**

> An illustrated iPhone game result screen. Warm ivory background. Centre-top: a
> small plush baby-faced cartoon sloth with a warm, gently delighted expression,
> arms slightly raised in a quiet celebration — not a big triumphant pose. Below:
> a short result line in large rounded semibold warm brown, then a cream card
> containing two or three lines of plain explanatory text. Beneath that, a soft
> rounded progress bar in butter yellow with a small collectible item icon at its
> end. Two buttons at the bottom: a filled sage-green primary and a bordered
> secondary. Soft storybook illustration, warm and kind, celebratory but quiet,
> no confetti, no score emphasis.

---

### S-21 · Collections

**Spec:** category tabs or filter · owned/locked · **source of unlock** ·
preview/equip/place/play.

**Built:** placeholder. Phase 8.

**Categories** (from IA §10): outfits · decor · plants · postcards · stamps ·
souvenirs · music · soundscapes · story scenes · theme variants.

**Design notes**

- Locked items **say how they're earned**. A mystery silhouette with no
  explanation is the anti-pattern here.
- Locked should be desirable, not sad — softly greyed with a clear route, not
  crossed out.
- Nothing earned is ever taken away. No expiry, no seasonal removal, no
  "available for 3 more days".
- Ten categories is a lot; the tab or filter treatment has to scale.

**States to mock:** grid with owned and locked mixed · a locked item's detail
showing its unlock route · a category with nothing owned yet · an item equipped.

**Prompt**

> An illustrated iPhone collectibles grid. Warm ivory background, a horizontal
> row of small capsule category chips at the top with one selected in butter
> yellow. Below, a three-column grid of soft cream tiles with 20pt rounded
> corners, each holding a small illustrated collectible object — a knitted hat, a
> tiny potted plant, a postage stamp, a paper lantern. Four tiles are fully
> coloured and warm; three are softly desaturated with a small lock icon and a
> tiny caption beneath explaining how they're earned. Soft storybook
> illustration, warm and inviting, locked items look appealing rather than denied.

---

### S-22 · Sunnie Home

**Spec:** scene canvas · Sunnie · edit/decor mode · outfit · music/ambience ·
travel nook · collection inspection · **static fallback under reduced motion.**

**Built:** placeholder. Phase 8.

**Design notes**

- This is the **only screen where Sunnie is the content**, not the framing.
  Everything else on the page serves the scene.
- The scene is a cosy room whose lighting, window, Sunnie's outfit, props, and
  audio transform across the day — the clearest expression of the Day-Cycle
  theme.
- Edit mode needs a completely different chrome from view mode, and the
  transition between them should be obvious.
- The travel nook is where souvenirs land — the payoff for the Travel tab.
- Under Reduce Motion the scene is static. Design the still frame as a real
  design, not a paused animation.

**States to mock:** the room in Sunnie Days, Sunnie Afternoonies, and Sunnie
Nights · edit/decor mode · outfit picker · an empty room at the start · Reduce
Motion still.

**Prompt**

> An illustrated cosy bedroom scene filling an iPhone screen, viewed straight on
> like a dollhouse room. Warm wooden floor, a large window with soft afternoon
> light and tropical leaves outside, a small bed with a lavender blanket, a shelf
> with three tiny collectible objects, a potted monstera, and a small corner
> table holding a souvenir postcard and a miniature globe. In the centre, a
> plush baby-faced cartoon sloth — light caramel fur, creamy ivory face mask,
> oversized glossy dark-brown eyes with warm highlights, peach-pink blush,
> butter-yellow quilted pyjamas with a small sun emblem — sitting contentedly
> holding a warm mug. Minimal UI: two small rounded buttons floating in the lower
> corners. Soft storybook illustration, warm and detailed, genuinely cosy.

---

### S-23 · Theme gallery

**Spec:** active theme · installed/locked · **preview in Sunnie Days, Sunnie
Afternoonies, Sunnie Nights** · audio preview · apply · accessibility preview.

**Built** (`Features/Themes/Screens/ThemesScreen.swift`): three themes listed
with the phase preview and apply. Audio preview and accessibility preview later.

**Themes:** Lush Tropical Jungle · Travel Scrapbook · Day Cycle.

**Design notes**

- The three-presentation preview is the whole point of the screen. Show all
  three side by side, named with their branded labels.
- **Audio previews never auto-play.** They require an explicit tap.
- Locked themes explain how they're earned, same rule as Collections.
- The accessibility preview shows the high-contrast variant — it belongs beside
  the normal preview, not buried in Settings.

**States to mock:** gallery with one active · a theme's three-phase preview
expanded · a locked theme with its unlock route · high-contrast preview.

**Prompt**

> An illustrated iPhone theme gallery. Warm ivory background. Each theme is a
> wide cream card with 24pt rounded corners containing three small side-by-side
> preview thumbnails showing the same scene in three different lightings — bright
> warm morning, saturated golden afternoon, deep blue-green night — each with a
> small caption beneath. The top card has a soft sage-green border and a small
> "Active" capsule. A lower card is softly desaturated with a small lock icon and
> a one-line caption. Each card has a small speaker icon button and a rounded
> "Apply" button. Soft storybook illustration, the three lighting states clearly
> and beautifully distinct.

---

### S-24 · Settings

**Spec:** profile · day cycle · notifications/quiet hours · audio · health ·
watch · calendar · location/weather · accessibility · iCloud/sync ·
export/delete · about/credits.

**Built** (`Features/Settings/Screens/SettingsScreen.swift`): day cycle, audio,
accessibility, notification permission, per-category reminder cadence, quiet
hours, privacy note. Health, Watch, calendar, location, sync, and export/delete
are later phases.

**Design notes**

- **Use standard native controls.** This is the one screen where the design
  system explicitly defers to platform convention (§12: "Settings: standard
  native clarity"). Theme the content, not the controls.
- Every reminder category starts at **None**. Nothing turns itself on, and
  granting notification permission does not enable any category by itself.
- Quiet hours **move** a reminder to the edge of the window; they never cancel
  it. The footer copy says so, and the design shouldn't contradict it.
- Permission rows must show current status honestly, including denied, with a
  route to Settings and a plain statement that the app works without it.
- Export and delete are real, serious controls. They get plain language and no
  decoration.

**States to mock:** notifications not determined · authorized (cadence section
appears) · denied · quiet hours on with pickers · ephemeral-storage warning.

**Prompt**

> An illustrated iPhone settings screen using standard native grouped-list
> conventions, gently themed. Warm ivory background (`#FFF8ED`) with white-cream
> grouped sections (`#FFF1DC`) and 12pt rounded corners. Rows show native
> controls: two toggle switches in sage green, a segmented picker, a menu picker
> showing "Once, and again later", and a disclosure row. Section headers in small
> muted brown caps-free type, with a two-line explanatory footer beneath one
> group in muted brown. No illustration inside the rows, no mascot — just clean
> native clarity in a warm palette. Soft storybook colour treatment, standard iOS
> structure.

---

### S-25 · Permission explainer

**Spec — before the system prompt:** state the benefit · state what data is
requested · state that permission is optional · offer **Not Now** · avoid asking
for unrelated data together.

**Built:** inline explanatory copy in Settings; no dedicated screen. Phase 9.

**Design notes**

- This screen exists so the system prompt is never the first time the user hears
  about a permission.
- **"Not Now" is a real, equally weighted choice.** Not a small grey link under a
  big blue button. The app is fully usable with every optional permission denied,
  and the design has to look like that's true.
- One permission at a time. Never bundle HealthKit and location into one ask.
- Sunnie may appear, but **never uses the nickname here** — a permission prompt
  is an ineligible context for "Noonies", along with warnings, errors, privacy
  copy, and serious travel notices.
- No urgency, no consequence framing, no "to get the most out of Sunnie Days".

**States to mock:** one per permission — notifications, HealthKit, location,
calendar, microphone, photos.

**Prompt**

> An illustrated iPhone permission explanation screen, warm and unhurried. Warm
> ivory background with generous whitespace. Centre: a small plush baby-faced
> cartoon sloth with a gentle, calm open-eyed expression, holding a small
> illustrated object relevant to the permission. Below, a short headline in large
> rounded semibold warm brown, then three short lines of plain explanatory body
> text in muted brown, generously spaced. At the bottom, two buttons of equal
> visual weight side by side — one filled soft sage green, one bordered in the
> same green with no fill, neither dominant. Soft storybook illustration, honest
> and calm, absolutely no urgency or pressure in the layout.

---

## 7. The theme × time-of-day grid

Every core screen must be tested in **three themes × three presentations**, plus
high contrast, Reduce Motion, and large Dynamic Type. That's the real design
surface, and the tokens above are one cell of it.

|  | Sunnie Days | Sunnie Afternoonies | Sunnie Nights |
|---|---|---|---|
| **Lush Tropical Jungle** | Dew, bright filtered greenhouse light, birds | Saturated warm sunlight | Deep green/blue, small lamps, soft insects or rain |
| **Travel Scrapbook** | Pale blue sky, fresh cream paper | Warmer postcard tones | Dark navy travel journal, moonlit stamps |
| **Day Cycle** | Cosy home, morning window | Golden afternoon room | Lamplit night room |

The time engine outputs **semantic modifiers**, not view code: lighting level,
warm/cool balance, background variant, card contrast variant, greeting category,
Sunnie expression/pose category, suggested activity, ambient audio category,
animation intensity, notification tone.

Practically, that means: **design the tokens, not the screens, per phase.** If a
screen only changes because its tokens changed, the grid is nine cheap variants.
If it changes structurally, it's nine expensive ones.

**Night presentations must retain readable contrast**, decorative lighting must
never hide status, and colour is never the sole status cue in any cell.

---

## 8. Prompt scaffolding

The per-screen prompts above are self-contained. When writing new ones, this is
the pattern they follow:

```
[Screen type] for [app description].
[Background + surface colours with hex].
[Corner radius, shadow character].
[Top-to-bottom content description, region by region].
[Sunnie's presence, size, pose, outfit — or explicitly none].
[Style: soft storybook illustration].
[Density and pacing].
[Explicit negatives].
```

**The Sunnie block, reusable verbatim:**

> a small plush baby-faced cartoon sloth — light caramel fur, creamy ivory face
> mask, oversized glossy dark-brown eyes with warm highlights, soft brown eye
> patches, small dark nose, small smiling mouth, peach-pink cheek blush, short
> soft eyebrows, small hair tuft, short compact body with short plush limbs and
> small rounded claws, head large relative to body

Add the outfit and pose per screen. Always pass the canonical reference images
alongside the prompt.

**Negatives worth repeating:** no red alarm colours · no badge counts · no
streak counters · no percentage-complete pressure · no emoji or face-based mood
scales · not a children's game · not a generic productivity dashboard · no tall
or adult-proportioned sloth · no realistic wildlife fur detail.

---

## Where things live

| What | Where |
|---|---|
| Canonical Sunnie references | `Documentation/Reference_Images/Canonical/` |
| Screen specs | `Documentation/03_UX/SCREEN_SPECIFICATIONS.md` |
| Navigation map | `Documentation/03_UX/INFORMATION_ARCHITECTURE.md` |
| Tokens, spacing, shapes | `Documentation/02_Character_and_Design/VISUAL_DESIGN_SYSTEM.md` |
| Theme and phase behaviour | `Documentation/02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` |
| Character rules | `Documentation/02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md` |
| Asset pipeline and manifest | `AssetsSource/ASSET_MANIFEST.md` |
| Implemented screens | `Apps/iOS/Features/*/Screens/` |
| Design tokens in code | `Apps/iOS/DesignSystem/DesignTokens.swift` |
| All user-facing copy | `Apps/iOS/Resources/en.lproj/Localizable.strings` |
| Locked decisions | `ARCHITECTURE_DECISIONS.md` |
