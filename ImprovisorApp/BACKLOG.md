# Backlog / feature requests

Small, tracked items outside the main step sequence. See
[NOTATION_EDITOR_PLAN.md](NOTATION_EDITOR_PLAN.md) for the large notation-editor
roadmap.

## Live tempo while playing
**Request:** moving the Tempo slider should adjust playback speed *in real time*
while a performance is playing, not only on the next Play.

**Current behavior:** tempo is applied when `SequencePlayer.play` is called; it
schedules each event against wall-clock time computed from a fixed tempo at start,
so a mid-playback slider change only takes effect on the next Play.

**Sketch of the fix:** give `SequencePlayer` a musical clock instead of baking
absolute times. Track a "musical position" (in slots) and convert to elapsed time
using the *current* `tempoBPM`, re-derived each wake. Options:
- Recompute the sleep target from live `secondsPerSlot` each loop iteration
  (expose an atomically-updatable `tempoBPM` on the player; `AppModel` writes it
  when the slider moves during playback), or
- Reschedule the remaining timeline whenever tempo changes.
Keep the pure `PlaybackTimeline` in slots; only the slot→seconds mapping is live.
`AppModel.tempo`'s `didSet` would push the new value into the active player.

**Effort:** small–medium. Not blocking; nice polish for practicing.
