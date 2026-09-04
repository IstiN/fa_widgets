# Widget state sync (tile ↔ fullscreen)

One widget app can have several LIVE instances at once: the launcher board
tile engine(s) and the fullscreen app engine. Each runs its own JS context
(the native runtime is single-viewport), so without help they drift apart —
start the timer fullscreen and the board tile keeps showing the old state.

The host (Fa ≥ the version shipping `JsAppEngine.stateSyncEvent`) keeps the
instances consistent through **storage**: it is the shared, persisted source
of truth, and every write is broadcast live to the app's other engines.

## Host contract (Fa app, `js_app_engine.dart`)

- `jsr.storage.set(key, value)` persists to `apps/<id>/storage.json`
  (existing behavior) AND delivers a reserved event to every OTHER live
  engine of the same app:
  `jsr.onEvent` receives `('state.sync', {appId, key, value, writer})`
  — one event per changed key, fire-and-forget.
- Boot always hydrates from `storage.json`, so a freshly opened fullscreen
  app sees whatever the board tile persisted, even before any event. A
  write that lands while a sibling is still BOOTING is replayed to it
  right after its start with `writer: 'boot'` — treat it like any other
  external `state.sync` (the `rev` guard makes it idempotent).
- Deleting a key broadcasts `value: null`.

## Widget contract

1. **Keep syncable state under a reserved `__`-prefixed key** (today:
   `__state`). Reserved keys are protocol state; never surface them in the
   UI as user data.
2. **`__state` is one JSON object** with the full snapshot plus guards:

   ```js
   {
     v: 1,               // protocol version
     rev: 7,             // bumped on EVERY write
     writer: 'w-x9k2',   // random per-instance id (Math.random at boot)
     ...app fields       // timers: mode, running, remaining, endsAt, completed
   }
   ```

3. **Wall clock is the countdown truth.** A running timer stores
   `endsAt` (epoch ms) instead of ticking the persisted number down;
   `remaining` is derived: `Math.max(0, Math.round((endsAt - Date.now()) /
   1000))`. No per-second broadcasts are needed — every instance ticks
   locally against the same `endsAt`.
4. **Persist on every transition** (start/pause/reset/skip/phase finish):

   ```js
   rev = Math.max(rev, lastSeenRev) + 1;
   jsr.storage.set('__state', snapshot());
   ```

5. **Adopt external changes** in `jsr.onEvent`:

   ```js
   if (actionId === 'state.sync') {
     if (payload.key !== '__state') return;
     var next = payload.value;
     if (!next || next.writer === myId) return;   // own echo
     if ((next.rev || 0) <= rev) return;          // stale
     rev = next.rev; lastSeenRev = rev;
     // ...copy app fields, restart/stop the interval, re-render...
     return;
   }
   ```

   **Adoption must never write back** — writing on adoption would loop the
   broadcast. The `rev <= lastSeenRev` check also makes echoes inert.
6. **Reserved event names** (`state.sync`, `back`, `llm.delta`,
   `tile.refresh`) must not be treated as UI actions in `onEvent`.
7. **Boot resolution**: on hydrate, if `running && endsAt <= now`, THIS
   instance resolves the expiry (advance the phase, count a completed
   pomodoro on focus, persist the bumped state) — whoever boots first
   after the deadline settles it.

## Race notes

Phase expiry on two instances in the same second: broadcasts land within
one host event-loop turn, long before the sibling's next 1 s tick, so in
practice the first resolver wins and the sibling adopts. If both still
resolve, the `rev` guard makes the final persisted state deterministic
(last write wins); a completed-pomodoro counter could in that rare case be
off by one — acceptable for timers, avoid for ledgers.
