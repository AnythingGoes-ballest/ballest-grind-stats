# Grind Stats

A plugin for the [Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager): how long
you've spent on every map in Ballest of Them All, how often you restarted it, and which checkpoints you get stuck at.

```
Chaos2
0:42:17
restarts 36   respawns 120   falls 12   finishes 3
checkpoint 3: 14 respawns, 2 falls
```

For every map you play (the game's own tracks and every workshop or local map), kept across launches:

- **Time**: all the time the map is on screen, including the pre-race menu and the pause menu. Watching a replay and
  the track editor don't count.
- **Restarts**: restarts from the beginning (Backspace, or R before the first checkpoint).
- **Respawns**: R at a checkpoint, counted for that checkpoint.
- **Falls**: falls into the kill zone, counted for the checkpoint the ball goes back to (or the start).
- **Finishes**: runs finished.

Checkpoints are numbered in the order you first reached them and recognised by where they are, so a checkpoint keeps
its number between sessions. Many of the game's own tracks have no checkpoints: there, R always restarts.

All of it comes from the game's own counters, not key presses, so rebinding keys changes nothing.

## Using it

- **While you play**, a small box shows this map's time and counts, and on maps with checkpoints the one you'd
  respawn at. Drag it anywhere while the cursor is on screen (the pause menu, for example).
- **grind stats** in the footer opens every map's stats: the totals across all maps, then each map with its picture,
  sortable by most time, most restarts, most recent or name. **details** shows a map's checkpoints (the one where
  the most went wrong stands out) and has **reset this map** (click it twice).
- **Settings** (footer **plugins** > **installed** > Grind Stats > **settings**): show or hide the box, its text
  size, and how dark its background is.

## Install

In the game: footer **plugins** > **browse** > Grind Stats > **install**. Needs the plugin manager host 0.18.0 or
newer.

## How it works

`main.as` uses the host's `Race` API (`Restarts`, `Respawns`, `Falls`, `CurrentCheckpoint`, `CheckpointPosition`,
`TrackKey`, `TrackImage`) and saves its numbers with `Storage`
(`%LOCALAPPDATA%\Ballest\Saved\PluginManager\storage\grind-stats.txt`).

## License

MIT
