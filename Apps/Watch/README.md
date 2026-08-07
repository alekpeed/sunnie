# Watch

The Apple Watch app. Foundations landed in Phase 2 for the vertical slice; the
five destinations and the four new actions are Phase 9.

```
Watch/
├── App/SunnieDaysWatchApp.swift       the five-page shell
├── Models/WatchModel.swift            state, and every outgoing action
├── Screens/WatchScreens.swift         Today, Plants
├── Screens/WatchFeatureScreens.swift  Check In, Calm, Travel
└── Integrations/WatchConnectivityClient.swift
```

## The Watch is a thin client

It renders a snapshot the phone already resolved. It has **no content pack, no
schedule maths, and no message selection** — the affirmation, the next task, the
practices, and the trip all arrive already chosen.

The one piece of real logic on the wrist is **action-key generation**. Every key
is created at the moment of the tap and travels with the action, which is what
makes a redelivered transfer resolve to the same record on the phone rather than
a second one (§7).

That key must survive the trip. The phone's use cases accept an explicit key and
source for exactly this reason — regenerating one from the phone's clock would
produce a different key and a duplicate entry.

## Everything is queued, nothing waits

Actions go out with `transferUserInfo`, which §7 assigns to queued background
actions. A tap made out of range is delivered when the phone is next reachable.
The wrist confirms the tap immediately and optimistically, so there is nothing
for the user to wait for and nothing to retry.

The optimistic set is cleared whenever a newer snapshot arrives: whatever the
phone now says is the truth.

## One envelope (ADR-028)

Every outgoing action is a `WatchActionEnvelope` carrying the five fields §7
requires. The phone routes on `kind` without decoding the body, so an action from
a newer build is *recognisably* unknown rather than a decode failure that looks
like corruption.

## Physical-device testing is required before release

§11 and TESTING_AND_QUALITY_STRATEGY: **queued WatchConnectivity transfers must
be tested on paired physical devices.** The Simulator does not faithfully
reproduce `transferUserInfo` queueing, delayed delivery, or redelivery, which are
the three behaviours everything above depends on.

What to exercise on real hardware, with the phone out of range for each:

1. Water a plant, tick a checklist item, save a check-in, finish a breathing
   practice, and log water — all with the phone off or far away.
2. Bring the phone back. Every action should arrive exactly once.
3. Repeat with the phone app killed rather than backgrounded. The care queue is
   durable; the other four rely on WatchConnectivity's own queue.
4. Force a redelivery and confirm nothing doubles.

None of this has been run. There is no paired hardware in this environment.
