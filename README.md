# Grind Stats

A plugin for the [Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager): how long
you've spent on every map in Ballest of Them All, how often you restarted it, and which checkpoints you get stuck at.

```
TOTAL       1:42:17
SESSION     12:05
ATTEMPTS    318  +41
FINISHES    27   +3
```

For every map you play (the game's own tracks and every workshop or local map), kept across launches:

- **Time**: all the time the map is on screen, including the pre-race menu and the pause menu. Watching a replay and
  the track editor don't count.
- **Restarts**: restarts from the beginning (Backspace, or R before the first checkpoint).
- **Respawns**: R at a checkpoint, counted for that checkpoint.
- **Falls**: falls into the kill zone, counted for the checkpoint the ball goes back to (or the start).
- **Finishes**: runs finished.
- **Played**: time actually racing: the race running, the game not paused, and the ball steered or jumped in the last
  five seconds (the idle rule of Trackmania's Grinding Stats).
- **Attempts**: runs started, the first start and every restart.

Checkpoints are numbered in the order you first reached them and recognised by where they are, so a checkpoint keeps
its number between sessions. Many of the game's own tracks have no checkpoints: there, R always restarts.

The counts come from the game's own counters, not key presses, so rebinding keys changes nothing; only played time
looks at steering and jumping, through the game's own input.

## Using it

- **While you play**, a card shows this map's played time, attempts and finishes, all-time and (in lime) this
  session. A session starts when the map is loaded; a restart keeps it, and leaving the track ends it. Drag the card anywhere while the cursor is on screen (the pause menu, for example).
- **F6** hides and shows the card until the game closes. **F8** writes this map's numbers to the plugin manager's log.
- **grind stats** in the footer opens every map's stats: the totals across all maps, then each map with its picture,
  sortable by most time, most restarts, most recent or name. **details** shows a map's checkpoints (the one where
  the most went wrong stands out) and has **reset this map** (click it twice), which clears every number the map has, played time and
  attempts too.
- **Settings** (footer **plugins** > **installed** > Grind Stats > **settings**): show or hide the card, its text
  size, and how dark its background is. Six more switches, all off by default, add rows to the card: the map's name,
  its time on the map (menus and pause included), restarts, respawns and falls (each with this session's count in
  lime), and the checkpoint you're on with its respawns and falls (on maps that have checkpoints).

## Install

In the game: footer **plugins** > **browse** > Grind Stats > **install**. Needs the plugin manager host 0.24.0 or
newer.

## How it works

`main.as` uses the host's `Race` API (`Restarts`, `Respawns`, `Falls`, `CurrentCheckpoint`, `CheckpointPosition`,
`TrackKey`, `TrackImage`, `RunId`, `IsPaused`, `GetInput`) and saves its numbers with `Storage`
(`%LOCALAPPDATA%\Ballest\Saved\PluginManager\storage\grind-stats.txt`).

## License

MIT
