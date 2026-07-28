# Themes and Time-of-Day System

## 1. Two separate concepts

Sunnie Days has:

1. A **universal time engine** that adapts every theme.
2. An optional **Day-Cycle Theme** with branded presentations.

Do not conflate them.

## 2. Universal internal phases

The engine may calculate these internal phases:

- `morning`
- `day`
- `afternoon`
- `evening`
- `night`
- `lateNight`

The calculation uses:

- Device local time
- Active trip time zone
- Optional current location and sunrise/sunset
- User override
- Quiet hours
- Optional sleep context, without making medical assumptions

Default clock fallback when sunrise/sunset is unavailable:

- Morning: 05:00–10:59
- Day: 11:00–13:59
- Afternoon: 14:00–17:59
- Evening: 18:00–20:59
- Night: 21:00–23:59
- Late night: 00:00–04:59

These ranges must be user-adjustable later if real use shows they are unsuitable.

## 3. Public branded labels

Only these branded labels are permitted:

| Internal context | Branded presentation |
|---|---|
| Morning and day | Sunnie Days |
| Afternoon | Sunnie Afternoonies |
| Evening, night, and late night | Sunnie Nights |

The app title remains Sunnie Days in every state.

## 4. Universal outputs

The time engine provides semantic modifiers rather than direct view code:

- Lighting level
- Warm/cool balance
- Background variant
- Card contrast variant
- Greeting category
- Sunnie expression/pose category
- Suggested activity category
- Ambient-audio category
- Animation intensity
- Notification-tone category

## 5. Initial theme families

### 5.1 Lush Tropical Jungle

Visual language:

- Layered tropical leaves
- Monstera, philodendron, orchids, bird of paradise, hibiscus
- Greenhouse light
- Warm wood and terracotta
- Water and soft jungle ambience

Time changes:

- Morning/day: dew, bright filtered light, birds
- Afternoon: saturated warm sunlight
- Night: deep green/blue, small lamps, soft insects or rain if enabled

### 5.2 Travel Scrapbook

Visual language:

- Cream paper
- Taped photos
- Stamps
- Map fragments
- Postcards
- Soft blue and coral accents
- Suitcase and camera details

Time changes:

- Morning/day: pale blue sky and fresh paper
- Afternoon: warmer postcard tones
- Night: dark navy travel journal, moonlit stamps, hotel-window ambience

### 5.3 Day-Cycle Theme

This theme explicitly celebrates the three names:

- Sunnie Days
- Sunnie Afternoonies
- Sunnie Nights

It uses a cozy home scene whose lighting, window, outfit, props, and audio transform during the day.

## 6. Theme definition

A theme package should define:

- Stable ID and version
- Display name
- Semantic palette values
- Typography overrides
- Background assets
- Decorative assets
- Card treatment
- Sunnie outfit IDs
- Sunnie Home assets
- Audio cue IDs
- Variants for internal time phases
- High-contrast overrides
- Reduced-motion behavior
- Minimum app version

## 7. Theme selection

- User may choose a fixed theme.
- Universal time modifications remain active unless manually disabled.
- User may preview each day phase.
- Audio previews do not auto-play without an explicit action.
- Locked themes explain how they are earned.

## 8. Manual controls

Settings should offer:

- Automatic day cycle on/off
- Preview phase
- Keep current theme fixed
- Ambient audio on/off
- Night brightness preference
- Use sunrise/sunset if location is permitted
- Travel time-zone behavior: current location, active destination, or home

## 9. Accessibility

- Night presentation must retain readable contrast.
- Decorative lighting changes must not hide status.
- Color is not the sole status cue.
- Continuous ambience and motion are optional.
- Reduce Motion switches to static or crossfade-only transitions.

## 10. Testing matrix

Every core screen must be tested in:

- All three initial theme families
- Sunnie Days presentation
- Sunnie Afternoonies presentation
- Sunnie Nights presentation
- High contrast
- Reduce Motion
- Large Dynamic Type
