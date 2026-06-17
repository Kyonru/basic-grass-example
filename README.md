# Stylised 3D Pixel Grass — LÖVE

A [LÖVE](https://love2d.org) (11.5) port of **Dylearn's** "3D Pixel Art Grass"
Godot demo: real 3D stylised pixel-art grass with wind, character displacement,
toon lighting and scrolling cloud shadows — extended with quality presets and a
one-command Raspberry Pi deploy workflow.

The original grass system, shaders and art are by **Dylearn**. This repository
is a LÖVE port and the original Godot project is included alongside it.

---

## Features

- Real 3D grass — orthographic camera, depth-tested billboard blades, hybrid
  toon lighting with world-space cloud shadows
- Quantised ("stepped") wind sway, fake perspective and view-space sway
- Character-reactive displacement (the capsules and player part the grass)
- Pixel-art look — the scene renders to a low-resolution canvas and is upscaled
  with nearest filtering
- **Quality presets** (low / medium / high) that scale both blade count and
  internal render resolution, auto-selected from the device
- **Instanced rendering with a non-instanced fallback**, so it runs on GPUs
  without vertex instancing (e.g. the Raspberry Pi)
- **One-command Raspberry Pi deploy** — build, upload, run and stream logs

---

## Run

Requires [LÖVE 11.5](https://love2d.org). From the repository root:

```sh
love love2d
```

### Controls

| Key   | Action                              |
| ----- | ----------------------------------- |
| Space | Toggle quantised (stepped) wind     |
| C     | Toggle character grass displacement |
| N     | Wind noise debug view               |
| R     | Re-scatter the grass field          |
| G     | Cycle quality (low / medium / high) |
| Esc   | Quit                                |

### Quality

Each preset sets a blade count and an internal render resolution (16:9,
upscaled to the window). The grass shader is fragment-heavy, so lowering the
resolution helps weak GPUs more than dropping blades does.

| Preset | Blades | Internal resolution |
| ------ | ------ | ------------------- |
| low    | 1000   | 128×72              |
| medium | 5000   | 256×144             |
| high   | 15000  | 384×216             |

The starting preset is detected from the device — GPUs without instancing (the
Pi) start at `low`. Force one with `love love2d --quality=low|medium|high`, or
cycle live with **G**. Counts and resolutions are easy to tune in `love2d/main.lua`.

---

## Raspberry Pi

`raspberry-pi.bash` builds the `.love`, uploads it over SSH, launches it on the
Pi's display and streams the log so a crash is visible immediately. Configure
the target in a `.env` file at the repository root:

```sh
RASPBERRY_PI_HOST=raspberrypi.local
RASPBERRY_PI_USER=pi
RASPBERRY_PI_DIR=/home/pi/games
LOVE_FILE=grass-demo.love
LOVE_SOURCE_DIR=love2d
```

Then:

```sh
./raspberry-pi.bash              # build, upload, run, stream logs
./raspberry-pi.bash --no-upload  # just restart what is already on the Pi
./raspberry-pi.bash --detach     # start it and exit
```

Build the `.love` on its own with `./zip.bash`.

---

## License

This project uses **two licences**, depending on what part of the repository you
are using:

### Code

All source code (scripts, shaders, and tools) is licensed under the
**MIT License**.

You are free to use, modify, and redistribute the code with minimal restrictions.

### Art Assets

All art assets (models, meshes, textures, and other visual content), except the
**Waterfowl logo**, are licensed under
**Creative Commons Attribution 4.0 (CC BY 4.0)**.

You are free to use, modify, and include the assets in commercial projects, **as
long as credit is given**.

#### Credit example

"[asset_name] asset(s) by Dylearn"

eg: "Grass assets by Dylearn"

### Logo

The **Waterfowl** project logo and branding assets are **not licensed** for
reuse. All rights are reserved. The logo may not be used, modified, or
redistributed without explicit permission.

---

## Credits

- Original "3D Pixel Art Grass" concept, grass system, shaders and art —
  **Dylearn**.
- LÖVE port and Raspberry Pi tooling — Roberto Amarante ([@Kyonru](https://github.com/Kyonru)).
