# Stylised 3D Pixel Grass — LÖVE port

A [LÖVE](https://love2d.org) (11.5) port of Dylearn's Godot "3D Pixel Art
Grass" demo in the repository root. It is real 3D, built the same way as the
original:

- A 640×360 offscreen canvas with a depth buffer, scaled up with nearest
  filtering for the pixel-art look (Godot: SubViewport + Sprite2D).
- An orthographic camera and directional light using the exact transforms
  from `Scenes/Demo.tscn`.
- 30,000 grass blades drawn with one instanced draw call
  (`love.graphics.drawInstanced`, Godot: MultiMesh). The vertex shader
  ports `Shaders/Grass.gdshader`: camera billboarding, quantised-time wind
  sway from two diverging scrolling noises, view-space sway, character
  displacement rotation, and the fake-perspective UV squish.
- Toon lighting with scrolling cloud shadows (`clouds.gdshaderinc`) on both
  the floor and the grass, sharing the same albedo-patch noise textures.
- Three translucent capsule characters that wander to random points in the
  bottom half of the camera view (`RandomPositionCharacter.gd`) and push
  the grass aside, with positions sent to the shader at 10 Hz
  (`CharacterManager.gd`).

The seamless `NoiseTexture2D` resources are generated at load time by
sampling `love.math.noise` on a 4D torus.

Not ported: the WATERFOWL katana model (glTF loading + the outline/dither
shaders are out of scope for this demo).

## Run

```sh
love love2d
```

(from the repository root, with LÖVE 11.5 installed)

## Controls

| Key   | Action                                  |
| ----- | --------------------------------------- |
| Space | Toggle quantised (stepped) wind         |
| C     | Toggle character grass displacement     |
| N     | Wind noise debug view                   |
| R     | Re-scatter the grass field              |
| G     | Cycle quality (low / medium / high)     |
| Esc   | Quit                                    |
