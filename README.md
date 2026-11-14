# Tessera Clock

A kinetic clock: a grid of small analogue clocks whose hands move together
through radial bursts, concentric rings and rolling waves, then gather to spell
the time.

Two shapes, alternating each time it starts:

- **Round** — a disc of clocks; the time appears as thin, broken line numerals
  while the surrounding hands rest on a diagonal.
- **Wide panel** — a long rectangle that fills a wide screen, with bold block
  numerals traced in outline.

## Browser

Open `index.html`. Move the mouse to show the options, or use the keys:

| Key | Option | Choices |
|-----|--------|---------|
| P | Shape | Alternate · Round · Wide panel |
| G | Round grid | Compact · Dense |
| S | Surface | Noir · Plaster · Bone |
| A | Around the time | Still · Drifting |

Options can also go in the address, e.g. `index.html?shape=panel&surface=plaster`.

## macOS screensaver

```sh
./build-saver.sh          # builds TesseraClock.saver
open TesseraClock.saver   # installs it
```

Then choose **Tessera Clock** in System Settings → Screen Saver. **Options…**
offers the same choices. The clock dims when you move the mouse or type, so the
password prompt stays readable.

The screensaver is a native port of `index.html` (a web view stays blank inside
macOS's screensaver host), so changes to one need making in the other.

## Full-screen app

```sh
swift run
```

Shows `index.html` full screen. Esc, Q or a click quits.

## License

MIT
