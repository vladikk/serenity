# Serenity

A macOS menu bar app for mixing ambient sounds, inspired by [A Soft Murmur](https://asoftmurmur.com).

## Sounds

The loops are built from freely licensed (CC0 / CC BY) recordings on [Freesound](https://freesound.org).
`tools/sounds.json` lists the sources for each sound; the noise sounds are generated with FFmpeg.

```sh
python3 tools/build_sounds.py          # all sounds (downloads ~25 recordings, takes a while)
python3 tools/build_sounds.py rain     # just one
```

The script checks each recording's license, downloads Freesound's HQ preview, joins multiple sources with
crossfades, makes a seamless loop, normalises loudness and writes `Sounds/<key>.mp4` plus `Sounds/credits.json`
(shown in Settings → Credits). Requires `ffmpeg`.

## Building

```sh
./build.sh                             # produces build/Serenity.app
cp -R build/Serenity.app /Applications/
```
