# Backend

Two things live here, and they answer to different audiences.

`contract/` is read by code. Each file is a set of fixtures that both the Swift
and the Kotlin test suites load, so a rule the two clients have to agree on fails
a test rather than a game. Nothing in it is deployed anywhere.

`supabase/migrations/` is read by a database. Nothing here has been applied yet —
see below.

## The contract files

| File | Pins |
|---|---|
| `move-fixtures.json` | The wire format of a move, byte for byte |
| `answer-fixtures.json` | Normalising, matching, and what counts as a near miss |
| `replay-fixtures.json` | The board the moves produce |
| `turn-fixtures.json` | Whose turn it is, the next sequence number, the action key |

The reason each of these is a file rather than a shared library is ADR-035: the
Android client is a second implementation of rules the iPhone already has, and
the duplication is the cost of the decision. These files are what stop the
duplication drifting silently. Edit one without changing both clients and CI goes
red on the Swift jobs and the Kotlin job at once.

When adding a rule both clients must agree on, add fixtures for it in the same
change. A rule pinned on one side only is a document, not a contract.

## Deployment status

**Nothing has been applied to any database.** `0001_multiplayer.sql` is written
and reviewed but unapplied, and no client is pointed at a project.

### The open decision: which project

The account has two Supabase projects:

| Project | State | Contents |
|---|---|---|
| `alekpeed's Project` (`ukqdbxxhxxafbcnkmskg`) | active | sharebox, profiles, sync records, push tokens — with live data in them |
| `polyglotai` (`qddglfcuipmazrjoxpin`) | inactive | — |

Neither is a Sunnie project. So the schema either joins the first or gets a new
one, and the two are not equivalent:

**Adding it to the existing project.** The migration was written for this — every
table is prefixed `sunnie_` rather than placed in its own schema, because a
non-public schema has to be added to the API's exposed list before PostgREST will
serve it, while a prefix survives being applied anywhere. Costs nothing extra.

The thing to check before choosing it is `auth.users`. Sunnie players are
pseudonymous, created by anonymous sign-in, and `sunnie_player.id` references
that table — which the existing project's `profiles` also depends on. If anything
there reacts to a new auth user, Sunnie players would start appearing in it.
That is a question about the existing project's triggers, not about this schema.

**A dedicated project.** No shared auth pool, no interaction with live data, and a
much easier privacy story to state plainly: one database, one purpose, game moves
only. It is a second project to keep alive, and creating one has a cost the
account holder should confirm rather than have inferred.

### What the privacy boundary does not depend on

Either choice keeps ADR-035's boundary intact, because the boundary is about what
is *sent*, not where it lands: journal entries, wellness check-ins, health
figures, plants, meals, trips, photos, audio, and preferences never reach the
network at all. The schema has nowhere to put them, which is deliberate —
widening it would be an obvious change rather than a quiet one.

The choice above is about blast radius and operational tidiness, not about
whether private data is exposed.

## Applying it, when the project is chosen

The migration is idempotent — `create table if not exists`, `create or replace
function`, `drop policy if exists` before each `create policy` — so it can be
re-run without a reset. Realtime publication is added only if absent.

After applying, the client needs the project URL and the publishable key, and
anonymous sign-in must be enabled in the project's auth settings. Neither belongs
in this repository.
