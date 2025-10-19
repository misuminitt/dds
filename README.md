# DDS – Star Job Automator
A Roblox delivery/teleport automation script with a custom GUI for the **Drag Drive Simulator** (DDS) map.  
Includes start-job automation, block scanning (1→8), manual teleport controls.

## Features
- **Start-Job Flow**: Auto teleport to Start, trigger “Start Job / Take Packages” prompt (triple), wait, and begin.
- **Scan & Drop**: Loop through blocks **1..8** (Faroka → Klaten), equip package, attempt drop (triple interact), detect success.
- **Main Tab (Job)**: Start/Stop loop, real-time log & status, **delay controls** (Start, After Start, Fail Next, Success Wait).
- **Teleport Tab**: One-click teleport to **Start Job** and each block **(1..8)**.
- **Settings Tab**: Toggle **keybind** to show/hide GUI, **theme switcher** (Dark/Light/Blue).

## Usage
To run this script in Roblox, execute the following command in your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/misuminitt/dds/main/DDS.lua"))()
````

> **Notes**
>
> * Default toggle key: `RightShift` (can be changed in **Settings** tab).
> * Default delays (seconds): Start=10, After Start=25, Fail Next=25, Success Wait=25 (editable in **Job** tab).
> * Tabs: **Job / Teleport / Settings**. Use **Teleport** when you want manual control; the loop auto-pauses while you interact.

## Credits

Made by **misuminitt**
