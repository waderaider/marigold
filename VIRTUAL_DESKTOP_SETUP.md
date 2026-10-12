# MARIGOLD PC VR — Virtual Desktop Setup (v0.7.0)

## What you need
- Windows PC with NVIDIA RTX 5070 Ti (or similar)
- MARIGOLD v0.7.0 Windows build (`Marigold-v0.7.0-windows.zip` from the GitHub Release)
- Meta Quest 3 with Virtual Desktop (paid app, ~$20 on Quest Store)
- Virtual Desktop Streamer app installed on your PC (free, from vrdesktop.net)
- Both PC and Quest on the same network (wired PC via Ethernet strongly recommended)

## Setup steps
1. **Install the Streamer**: Download and install Virtual Desktop Streamer on your PC. Enter your Meta username.
2. **Extract MARIGOLD**: Unzip `Marigold-v0.7.0-windows.zip` to a folder (e.g. `C:\Games\Marigold`).
3. **Launch Virtual Desktop** on your Quest 3. Connect to your PC.
4. **Start MARIGOLD**: On the PC (or via Virtual Desktop's "Launch" — point it at `Marigold.exe`), run `Marigold.exe`. The game launches in VR mode automatically when an OpenXR runtime is active.
5. **Put on the headset**: You should see the MARIGOLD menu in VR, streamed from your PC.

## Recommended Virtual Desktop settings
- **Codec**: HEVC (H.265) — best quality/bandwidth on RTX cards. Fallback: H.264+ if you see artifacts.
- **Bitrate**: 150 Mbps (wired) / 100 Mbps (Wi-Fi 6). Higher = sharper, but needs the bandwidth.
- **Resolution**: Set "VR Graphics Quality" to Ultra in Virtual Desktop; in MARIGOLD's Settings (menu button → Settings), set Graphics to **Ultra** for the full Forward+ showcase (SDFGI, SSR, SSAO, volumetric fog).
- **Refresh rate**: 90 Hz (Virtual Desktop) — MARIGOLD targets 72fps on Quest standalone; on PC it can push higher.
- **Sliced encoding**: ON (reduces latency).

## Controls
- **Controllers**: Standard OpenXR — same as Quest standalone. Laser pointer + trigger for menus and teleport.
- **Menu button**: Opens the pause menu (same as Quest).
- **Hands**: Hand tracking works if enabled in Virtual Desktop (may have higher latency than Quest native).

## What’s different from Quest standalone
- **Graphics**: Forward+ renderer with SDFGI global illumination, screen-space reflections, SSAO, volumetric fog, and bloom. This is the "Pixar look" showcase — dramatically better lighting than the Quest build.
- **Performance**: Uncapped particle counts, higher-resolution textures, full dynamic shadows (1 directional light).
- **Same content**: All 5 chapters + 6 experiences, same teleport, same settings, same telemetry (reports as `PCVR-VirtualDesktop` so we can tell PC sessions apart).

## Troubleshooting
- **Black screen**: Ensure Virtual Desktop Streamer is running on the PC and the Quest is connected. Try launching `Marigold.exe` from the PC desktop first.
- **No VR mode**: MARIGOLD uses OpenXR. Virtual Desktop provides an OpenXR runtime — ensure "OpenXR" is enabled in Virtual Desktop Streamer settings.
- **Stuttering**: Lower the Virtual Desktop bitrate, or set MARIGOLD's Graphics to High instead of Ultra.
- **Controllers not tracked**: Ensure controllers are awake (press any button). Virtual Desktop streams them as standard OpenXR controllers.

## Version
- PC build version: 0.7.0 (same as Quest APK — version parity verified).
- Check the in-app version badge (launcher header) to confirm.
