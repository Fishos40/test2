# Minecraft HUD for Monster Hunter Wilds

A Monster Hunter Wilds mod that brings Minecraft's blocky survival HUD into the hunt.

## Features

- **Hearts for health** – ten pixel-art hearts track your hunter's health in half-heart steps.
- **Drumsticks for hunger** – a row of drumsticks shows your max stamina. It shrinks the longer you hunt and fills back up when you eat, just like hunger.
- **Experience-style stamina bar** – your current stamina drains and refills in a green segmented bar where Minecraft's XP bar sits.
- **Damage flash** – hearts flash white when you take a hit.
- **Low-health shake** – hearts jitter when you're down to your last two.
- **Settings menu** – in the REFramework menu (Insert key → Script Generated UI → Minecraft HUD) you can toggle each part, change the pixel size and move the HUD up or down. Settings are saved.

All pixel art is original and drawn live by the script. The mod ships no Minecraft or Monster Hunter assets.

## Requirements

- Monster Hunter Wilds on PC (Steam)
- [REFramework](https://github.com/praydog/REFramework-nightly/releases) for Monster Hunter Wilds

Works in solo and online hunts. The HUD shows only on your own screen, so other hunters in your session don't need the mod.

## Manual install

Copy the `reframework` folder from the release zip into your Monster Hunter Wilds game folder, next to `MonsterHunterWilds.exe`.

## Building

`./build.sh` writes `dist/MinecraftHUD-<version>.zip`.
