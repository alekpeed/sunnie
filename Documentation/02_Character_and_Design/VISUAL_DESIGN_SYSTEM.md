# Visual Design System

## 1. Design direction

Sunnie Days should resemble a polished illustrated companion app, not a children’s game and not a generic productivity dashboard. The visual language combines warm storybook softness, plush character art, rounded native controls, and clear modern information hierarchy.

Generated concept images establish mood, character warmth, palette direction, and decorative language. They do not establish final text, exact navigation, or production-ready spacing.

## 2. Design principles

- Sunnie is the visual focus where appropriate.
- Information remains legible and actionable.
- Decorative elements frame content rather than compete with it.
- Adult usability takes priority over novelty.
- Every theme uses the same semantic design tokens.
- Night presentation must be genuinely comfortable in low light.
- Accessibility variants are part of the theme system.

## 3. Provisional core palette

These values are starting tokens. Final production colors may be tuned after asset creation and contrast testing.

| Token | Provisional value | Use |
|---|---|---|
| `canvasWarm` | `#FFF8ED` | Default background |
| `surfaceCream` | `#FFF1DC` | Cards and sheets |
| `surfaceRaised` | `#FFFDF8` | Elevated controls |
| `textPrimary` | `#493528` | Main text |
| `textSecondary` | `#755E4D` | Secondary text |
| `peach` | `#F3A58D` | Warm accent and wellness |
| `butter` | `#F6D47D` | Sunnie/day accent |
| `lavender` | `#B9A6E1` | Calm/night accent |
| `sage` | `#A9C5A0` | Plant accent |
| `sky` | `#A8CBE4` | Travel accent |
| `successSoft` | `#91B982` | Completion without alarm |
| `warningSoft` | `#D7A65A` | Noncritical attention |
| `errorSoft` | `#C97972` | Genuine errors only |

Do not use bright red as the default overdue-task language. Overdue care should use neutral attention treatment unless the user has configured stronger alerts.

## 4. Typography

Use Apple system fonts for the initial build.

- Headings: system rounded design where available
- Body: standard system text for maximum readability
- Numeric timers and data: monospaced digits where useful
- Minimum body size follows Dynamic Type rather than fixed pixels
- Avoid all-caps paragraphs
- Decorative script type may appear only in static artwork, never essential UI text

## 5. Spacing and layout

Use an 8-point base grid with 4-point exceptions for compact internal spacing.

Recommended tokens:

- `spaceXXS`: 4
- `spaceXS`: 8
- `spaceS`: 12
- `spaceM`: 16
- `spaceL`: 24
- `spaceXL`: 32
- `spaceXXL`: 48

Content should respect safe areas. Core controls must remain reachable on large phones. Long dashboards use vertical scrolling rather than compressed cards.

## 6. Shapes

- Primary cards: 20–28 point continuous corner radius
- Compact chips: capsule
- Buttons: 14–20 point radius or capsule depending on width
- Sheets: native system presentation with themed content
- Images: rounded rectangles or soft cutout art
- Use stitched, scrapbook, or leaf-shaped decoration as overlays, not as the only interactive hit target

## 7. Shadows and depth

Use subtle warm shadows. Avoid heavy floating-card stacks.

- Default card shadow: low opacity, small blur
- Elevated modal or important collectible: moderate shadow
- Night mode: reduce shadow reliance and use tonal separation
- Never rely on shadow alone to show interactivity

## 8. Icons

- Use SF Symbols for functional controls.
- Use custom illustrated icons for theme, collectibles, plants, travel stamps, and Sunnie-specific categories.
- Functional icons require text labels when meaning may be ambiguous.
- Avoid mixing detailed rendered icons with tiny thin-line icons in one control row.

## 9. Cards

Every dashboard card should answer:

1. What is this?
2. What is the current state?
3. What is the next action?

Cards must not become miniature full screens. Detailed content belongs after navigation.

## 10. Motion

Current release motion may include:

- Soft scale or bounce on successful completion
- Crossfade between day phases
- Gentle parallax or layered ambience where inexpensive
- Small Sunnie blink, wave, stretch, or breathing loops if assets exist
- Card insertion/removal transitions
- Haptic confirmation

Motion must stop or simplify under Reduce Motion. Avoid continuous large movement on task-heavy screens.

## 11. Haptics

- Light selection for picker changes
- Soft success for completed care or puzzle
- Gentle warning only for real attention states
- No repetitive haptic pressure
- Haptics may be disabled independently

## 12. Information density

- Today: medium density, progressive disclosure
- Jungle list: higher density with filters and bulk actions
- Travel: context-dependent; maps may be visually rich
- Wellness: lower density and calming pacing
- Games: tailored per mechanic
- Settings: standard native clarity

## 13. Empty states

Empty states should be useful, not merely decorative.

Example:

- No plants: Sunnie with a small pot, plus “Add your first plant”
- No trip: Sunnie at home, plus “Plan a trip” or “Add a past trip”
- No journal entries: a blank scrapbook with a clear “New entry” action

## 14. Generated-image caution

Text and controls shown inside concept images may contain errors or placeholder ideas. Do not copy them literally. Production UI must follow the documents and native interaction conventions.
