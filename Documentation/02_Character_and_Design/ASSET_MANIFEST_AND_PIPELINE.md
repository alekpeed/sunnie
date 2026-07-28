# Asset Manifest and Pipeline

## 1. Reference assets included in this package

### Canonical character references

| File | Role |
|---|---|
| `Sunnie_Canon_01_Character_Sheet.png` | Primary proportions, face, poses, palette, youthfulness |
| `Sunnie_Canon_02_Sleep_Concept.png` | Sleep, pillow, nightcap, soft-night presentation |
| `Sunnie_Canon_03_Wellness_Concept.png` | Wellness, journal, mood, and interface mood reference |

### Context-only references

| File | Role | Warning |
|---|---|---|
| `Sunnie_Flight_Attendant_Paris_Context_Only.png` | Paris composition, uniform idea, suitcase | Character is too mature/tall; redraw canonically |
| `Sunnie_Garden_Context_Only.png` | Tropical garden, watering action, lush scene | Character is too mature/tall; redraw canonically |

## 2. Production asset categories

- Character bases
- Faces and expressions
- Outfits
- Props
- Home environments
- Theme backgrounds
- Destination backgrounds
- Plant illustrations
- Travel stamps and postcards
- Collectibles
- Game art
- Icons
- Ambient loops
- Music
- Haptics metadata

## 3. Naming convention

Use stable descriptive names:

```text
sunnie_pose_sitting_happy_v001
sunnie_face_sleepy_half_lidded_v001
sunnie_outfit_flight_navy_v001
sunnie_prop_watering_can_brass_v001
theme_jungle_bg_today_day_v001
destination_paris_postcard_001
collectible_outfit_beret_001
```

Do not use names such as `final2`, `newnew`, or `image1`.

## 4. Source and runtime separation

Recommended repository structure:

```text
AssetsSource/             # editable source files, not all included in app target
CreatorAudioSource/       # MIDI sessions, stems, notes
SunnieDays/Assets.xcassets/
SunnieDays/Resources/ContentPacks/
SunnieDays/Resources/Audio/
```

Source files remain outside the runtime bundle when not required.

## 5. Image formats

- PNG for transparent rendered character assets
- HEIF/JPEG for photographic journal and travel images
- SVG/PDF vector assets only where Xcode asset support and visual needs make sense
- Use asset catalog variants for scale and appearance
- Avoid unnecessarily huge images in scroll views
- Generate thumbnails for lists

## 6. Character layering

For simple motion and outfit reuse, separate where practical:

- Body
- Face
- Eyes
- Mouth
- Foreground arm
- Outfit
- Prop
- Shadow

Do not over-fragment assets until animation requirements justify the complexity.

## 7. Audio formats

- Creator source: MIDI, DAW project, stems
- Shipping music: AAC/M4A or CAF where appropriate
- Short effects: CAF or high-quality compressed asset as appropriate
- Ambient loops: seamless encoded files tested for gapless playback
- Narration later: separate localized assets

## 8. Content ownership and credits

Every asset manifest entry should record:

- Stable ID
- File name
- Creator/source
- License or private-use status
- Version
- Feature/theme association
- Localization dependency
- Whether it may ship publicly

## 9. Airline assets

Airline-specific marks must live in an isolated optional asset group. Core components should refer to semantic IDs such as `flightUniformAccent`, not hardcoded logo file names. This allows private Delta-inspired presentation to be replaced if distribution changes.

## 10. Placeholder policy

If production art is missing:

- Use a clearly labeled placeholder.
- Preserve final dimensions and accessibility labels.
- Record the missing asset in the backlog.
- Do not generate a new canonical character interpretation without approval.

## 11. Asset QA

Check:

- Correct character age and proportions
- Transparent-edge quality
- Dark/night contrast
- File size
- Scale variants
- Localization safety
- Reduced-motion fallback
- No unlicensed third-party branding in distributable assets
