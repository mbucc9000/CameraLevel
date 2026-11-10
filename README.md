<img src="icon.png" width="80" align="right" alt="">

# CameraLevel

The level from newer iPhones' Camera, on the iOS 6 Camera grid: a line that tilts with the phone and turns yellow when your shot is level.

## Features

- A line in the middle of the Camera grid tilts as you tilt the phone, so you can see how straight your shot is.
- Get it level and the line closes up and turns yellow, like on newer iPhones.
- Works in portrait and landscape, for photos and videos. It shows up when you're close to level and hides when you point down at the floor.
- Shows whenever Grid is on.

## How to use

1. In Camera, tap Options and turn Grid on.
2. Hold the phone about level: a line shows in the middle of the grid.
3. Tilt until the line closes up and turns yellow, then take the shot.

## Requirements

- Jailbroken iOS 6 (tested on an iPhone 5 with iOS 6.1.2)
- Cydia Substrate (Cydia installs them for you)

## Install

In Cydia, add `https://mbucc9000.github.io/slopkit/` and install **CameraLevel**. Or download the `.deb` from [Releases](../../releases) and install it with `dpkg -i`.

## Building

[Theos](https://theos.dev) with the iOS 6.1 SDK: `make package FINALPACKAGE=1`.

## License

MIT.
