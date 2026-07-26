# Recording the demo GIF

A 15-second terminal demo at the top of the README is the single highest-ROI asset for
conversion (scroll → star). This guide gets you a clean recording in one take.

`scripts/demo.sh` is the scripted walkthrough — deterministic, paced for humans, and free (it
does **not** call the paid `claude` CLI; it shows the workflow lines). Record *that*.

## Option A — asciinema → GIF (recommended, crisp + small)

```bash
brew install asciinema agg          # agg = asciinema gif generator (or: cargo install --git https://github.com/asciinema/agg)

# Record (Ctrl-D or `exit` when demo.sh finishes)
asciinema rec demo.cast -c "bash scripts/demo.sh"

# Convert to GIF
agg --theme monokai --font-size 20 demo.cast docs/launch/demo.gif
```

Tips:
- Terminal at **~90×28**, a dark theme, a legible font (JetBrains Mono / Fira Code ~20pt).
- `DEMO_SPEED=1.1 asciinema rec …` for a slightly slower, more readable cadence.
- Keep it **under 20s** — trim dead air. Loop-friendly.

## Option B — VHS (scripted, fully reproducible, no hand-timing)

[charmbracelet/vhs](https://github.com/charmbracelet/vhs) records from a `.tape` script, so the
output is byte-identical every run — ideal for regenerating on each release.

```bash
brew install vhs
vhs docs/launch/demo.tape          # writes docs/launch/demo.gif
```

A starter `demo.tape`:

```tape
Output docs/launch/demo.gif
Set FontSize 20
Set Width 1100
Set Height 620
Set Theme "Monokai Pro"
Type "bash scripts/demo.sh" Enter
Sleep 18s
```

## Option C — plain screen recording

Record your terminal with QuickTime / OBS, run `bash scripts/demo.sh`, then convert:

```bash
ffmpeg -i demo.mov -vf "fps=12,scale=1000:-1:flags=lanczos" docs/launch/demo.gif
```

## After you have the GIF

1. Save it to `docs/launch/demo.gif`.
2. Uncomment the demo line near the top of `README.md`:
   ```markdown
   ![claude-init demo](docs/launch/demo.gif)
   ```
3. For an even better README hero, record a **real** `/kickoff` session building a tiny app and
   use that instead — nothing sells the harness like watching it ship.
