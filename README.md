# Qrawller Terminal

A minimal, dark, red, very animated "hacker" dashboard: a cinematic intro, a terminal, and an
interactive world map where you pin **victim** and **place** markers with your own notes.
Built with Lua + [LÖVE](https://love2d.org).

The hacking commands are fake theatre. Nothing touches your real network.

## What's in it

- **Intro**: a spinning dotted globe with link arcs, the logo assembling from flying pixels, a
  shockwave, and a loading sequence. Any key skips it.
- **World map**: drag to pan, mouse wheel to zoom.
  - **◆ VICTIM** marker: name, age, date of birth, date of death, IP, address, and an "anything else" box.
  - **○ PLACE** marker: name and a description.
  - Pick a tool, click the map to drop a marker, then type its details in the editor under the map
    (Tab jumps to the next field). Drag a marker to move it. Use the list to search and filter.
  - Markers save automatically to `markers.lua` in the save folder
    (`%APPDATA%\qrawller\` on Windows, `~/Library/Application Support/qrawller/` on Mac).
  - **Photos**: drag image files onto the window to attach them to the selected marker. They show
    in the editor, as a thumbnail on the map, and full-screen when clicked.
- **Files panel** (the FILES tab, or `files` / F3): a real file vault stored under the save folder.
  Make folders and text documents, import images and any other files by dragging them onto the window,
  edit text in place, preview images (list or grid view), rename, delete, and open the folder on disk.
- **Terminal**: `help` lists everything. Map: `markers`, `locate <name>`, `dossier <name>`.
  Files: `ls`, `cat <file>`, `mkdir <name>`, `write <file> <text>`, `files`.
- **Sound**: dark synthesized sounds (sub-bass hits, distortion, reverb) and a low ambient drone.
  Turn them off with `sound off`, or set `ambient = false` in `config.lua`.

## Run it

**Windows:** unzip `dist/QrawllerTerminal-win64.zip` and double-click `QrawllerTerminal.exe`
(keep the `.dll` files next to it). Every push also builds a fresh copy under the repo's **Actions** tab.

**Mac:** unzip `dist/QrawllerTerminal-macos.zip` and open `QrawllerTerminal.app`. The first time,
macOS will block it because it isn't signed: go to **System Settings → Privacy & Security** and click
**Open Anyway** (on older macOS you can instead right-click the app → **Open**).

**From source (any OS):** install LÖVE 11.5 and run `love .` in this folder.

## Controls

| | |
|---|---|
| `tab` | autocomplete a command |
| `↑` `↓` | command history |
| `ctrl+c` | stop the running command |
| `ctrl+l` | clear |
| `pgup` `pgdn` / mouse wheel | scroll |
| `F2` | show/hide the side panel |
| `F3` | switch tab (MAP / FILES) |
| `esc` | cancel placement / close viewer or editor |
| `F11` | fullscreen |
| click a panel title | collapse it |

## Add your own stuff

### Commands (type them in the terminal)

Copy `commands/_template.lua` to a new file in `commands/`, edit it, then type `reload` in the terminal.

```lua
return {
    name = "greet",
    help = "say hello",
    run = function(t, args)
        t.type("hello, {accent}" .. (args[1] or "stranger") .. "{}!")
        t.progress("calibrating vibes", 1.2)
        t.banner("HI")
        t.sound("ok")
    end,
}
```

The full list of `t.` tools (typewriter, decode, progress bars, banners, ask for input, shake, glitch,
sounds, …) is at the top of `commands/_template.lua`.

### Widgets (panels next to the terminal)

Copy `widgets/_template.lua` to a new file in `widgets/`, edit it, then type `reload`.

```lua
return {
    title = "MY PANEL",
    order = 5,       -- position in the column
    height = 80,     -- or "fill"
    draw = function(w, ui, x, y, width, height)
        if ui.button("go", "LAUNCH", x, y, 120, 28) then
            ui.run("countdown 3")   -- types and runs a terminal command
        end
    end,
}
```

### Without rebuilding the exe

The exe also loads `.lua` files from `%APPDATA%\qrawller\commands\` and `%APPDATA%\qrawller\widgets\`.
Drop files there and type `reload`.

### Rebuilding the exe

- **On Windows:** double-click `tools\build-windows.bat` → `dist\QrawllerTerminal-win64\`
- **On Mac/Linux:** `./tools/build.sh` → `dist/QrawllerTerminal-win64.zip` and `dist/QrawllerTerminal-macos.zip`
- **Or** push to GitHub and download the build from the Actions tab.

### Settings

`config.lua`: prompt text, theme (`red`, `mint`, `cyan`, `violet`, `amber`, `ice`, `mono`), font size,
glow strength, sounds, boot animation, aliases, and commands to run on start.

## Project layout

```
main.lua            start-up and LÖVE callbacks
config.lua          your settings
src/terminal.lua    terminal: output, input, animations
src/ui.lua          dashboard layout + button/toggle/graph toolkit
src/api.lua         the `t` toolkit given to commands
src/fx.lua          glow, ripples, sparks, glitch, matrix rain
src/sound.lua       sounds generated in code (no audio files)
src/intro.lua       the start-up animation
src/world.lua       land data -> map dots and globe points
src/markers.lua     marker storage + photos (shared by the map and commands)
src/vault.lua       the file vault (folders, documents, imported files)
src/images.lua      image loading/caching + full-screen viewer helpers
assets/worldmask.lua  0.5° land mask (from global-land-mask, MIT; NOAA GLOBE data, public domain)
commands/           terminal commands, one file each
widgets/            panels: worldmap.lua (MAP tab), files.lua (FILES tab)
tools/              build scripts
```

## Ideas to add next

**Panels**
- **Links between markers**: draw glowing connection lines between victims and places ("seen at", "lives at").
- **Timeline**: a scrubber under the map that shows markers by their dates.
- **File browser**: browse a fake file system of a hacked machine. Double-click files to "decrypt" them.
- **Password cracker**: pick a hash, choose wordlist/brute-force, and watch guesses scroll by with a live attempts/sec graph.
- **Radar sweep**: a rotating radar that finds "devices" as blips. Click one to scan it.
- **Mission board**: small objectives ("own 5 nodes", "decrypt 3 packets") with XP and a rank in the top bar.
- **Chat / intercept log**: a fake operator who sends you messages and hints, reacting to what you do.
- **Hex editor**: a scrolling hex view where clicking bytes flips them and makes the screen glitch.
- **Signal / waveform**: an oscilloscope that wobbles when sounds play.
- **Real system info**: battery, real clock, uptime, and real disk usage (`love.filesystem`).

**Commands**
- `ssh <node>` opens a fake remote shell with its own prompt and filesystem (`ls`, `cd`, `cat`).
- `firewall`: a mini-game. Type the falling words before they hit the bottom.
- `virus`: windows-within-the-window pop up and you click to close them.
- `weather <city>` / `crypto` with ASCII charts (fake data, or real data via an HTTP library).
- `todo` / `notes`: actually useful, saved with `love.filesystem.write`.
- `snake`, `pong`, or `typing-test` inside the terminal.
- `achievements`: unlocks for owning every node, finding the `breach` password, etc.

**Polish**
- A custom `.exe` icon (use [rcedit](https://github.com/electron/rcedit) on Windows).
- A CRT mode toggle: curved screen, scanlines, stronger bloom.
- Ambient background hum that rises while a command is running.
- Saving network-map progress between sessions.
