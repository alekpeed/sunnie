# Front page image brief

A package for handing to an image generator: what Sunnie Days is, what Sunnie
looks like, and how a front-page image should be laid out.

## The one distinction that matters

Two very different kinds of thing are in here, and treating them the same would
either produce an off-model character or needlessly box in the design.

**Locked — the character.** Sunnie's age, proportions, face, and emotional
register are fixed by `SUNNIE_CHARACTER_BIBLE.md`, and `CLAUDE.md` is explicit
that he must not be redesigned as tall, mature, realistic, lanky, or
adult-proportioned. A generator will drift toward exactly those if not told
otherwise, every time. `01_CHARACTER.md` is the part to paste into every prompt
without editing.

**Free — everything else.** Composition, crop, camera angle, props, background,
how many phones are in shot, whether there are phones at all. The canonical
concept art is a **style target, not a template**: match its warmth and its
medium, and then compose whatever serves the image. Nothing here is asking for a
reproduction of it.

The app facts in `02_THE_APP.md` sit in between — not artistic constraints, just
true things. An image showing four tabs when the app has five is wrong in the way
a typo is wrong, not in the way a design choice is wrong.

## What is in here

| File | Use |
|---|---|
| `01_CHARACTER.md` | Sunnie's invariants. **Paste into every prompt.** |
| `02_THE_APP.md` | What the app really is — tabs, screens, day cycles, tone |
| `03_PROMPTS.md` | Ready-to-paste prompts. Starting points, not a script |
| `palette.svg` | The shipped colours, as a visual swatch |

Also attach, wherever the tool takes an image reference:

`Documentation/Reference_Images/Canonical/Sunnie_Canon_01_Character_Sheet.png`

That sheet carries the character better than any paragraph can. The prose exists
for the tools that will not take a reference image, and as the thing to check a
result against.

## Two corrections worth knowing before you start

**The concept art is out of date in one specific way.**
`Sunnie_Canon_03_Wellness_Concept.png` shows a four-tab app — Home, Journal,
Stats, Me — described as "a cozy mood journal". The built app has **five** tabs
(Today, Jungle, Travel, Wellness, More) and is much more than a journal. Lovely
image; wrong tab bar. It is an easy detail to carry forward into a whole set of
images before anyone notices.

**Generators cannot spell.** Text inside a generated image comes out garbled far
more often than not. The prompts default to asking for soft placeholder lines
where text would go, with real type laid over afterwards — which is what a
designer would do anyway. `03_PROMPTS.md` says where to change that if you would
rather take the gamble on a short word.

## Colours

`palette.svg` is generated from `themes.v1.json` — the app's own content pack —
so it is what the built app actually renders, not a guess at it. Regenerate it if
the theme ever changes; the values are not copied by hand anywhere.
