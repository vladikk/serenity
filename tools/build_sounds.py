#!/usr/bin/env python3
"""Builds Serenity's sound loops from freely licensed Freesound recordings.

For each sound in tools/sounds.json: fetch the source pages (verifying the license is CC0 or CC BY),
download the HQ previews, join multiple sources with crossfades, turn the result into a seamless loop,
normalise loudness, and encode to AAC. Writes Sounds/<key>.mp4 and Sounds/credits.json.

Usage: python3 tools/build_sounds.py [sound ...]
"""
import html
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".cache" / "sources"
OUT = ROOT / "Sounds"
UA = {"User-Agent": "Mozilla/5.0 (Serenity sound builder)"}

MAX_TOTAL = 480         # seconds of material per sound, before looping
MAX_PER_SOURCE = 300
SKIP_START = 2.0        # field recordings often start with handling noise
JOIN_FADE = 3.0
LOOP_FADE = 6.0
TARGET_LUFS = -23.0
MAX_TRUE_PEAK = -1.5
MAX_LIMITING_DB = 8.0   # how far a limiter may tame transients (crackles, ticks) to reach the target
NOISE_SECONDS = 90

LICENSES = {
    "publicdomain/zero/1.0": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "licenses/by/3.0": ("CC BY 3.0", "https://creativecommons.org/licenses/by/3.0/"),
    "licenses/by/4.0": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
}


def run(args, capture=False):
    result = subprocess.run(args, check=True, text=True,
                            stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    return result.stdout if capture else result.stderr


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def source_info(user, sound_id):
    page_url = f"https://freesound.org/people/{user}/sounds/{sound_id}/"
    page = fetch(page_url)
    found = sorted(set(re.findall(r"creativecommons\.org/((?:licenses|publicdomain)/[a-z0-9+-]+/[0-9.]+)", page)))
    if len(found) != 1 or found[0] not in LICENSES:
        raise SystemExit(f"{page_url}: license {found} is not CC0 / CC BY")
    preview = re.search(r"https://cdn\.freesound\.org/previews/[^\"']+-hq\.mp3", page)
    if not preview:
        raise SystemExit(f"{page_url}: no preview found")
    title = re.search(r'<meta property="og:title" content="([^"]*)"', page)
    duration = re.search(r'data-duration="([0-9.]+)"', page)
    name, license_url = LICENSES[found[0]]
    return {
        "title": html.unescape(title.group(1)) if title else f"Sound {sound_id}",
        "author": urllib.parse.unquote(user),
        "url": page_url,
        "license": name,
        "licenseUrl": license_url,
        # The HQ ogg preview is higher quality than the mp3 one and sits next to it.
        "preview": preview.group(0).replace("-hq.mp3", "-hq.ogg"),
        "duration": float(duration.group(1)) if duration else None,
    }


def duration_of(path):
    return float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                     capture=True).strip())


def download(info, sound_id, limit):
    dest = CACHE / f"{sound_id}-{int(limit)}.wav"
    if dest.exists():
        return dest
    CACHE.mkdir(parents=True, exist_ok=True)
    total = info["duration"] or limit
    start = SKIP_START if total > 60 else 0
    tmp = dest.with_suffix(".part.wav")
    run(["ffmpeg", "-y", "-v", "error", "-user_agent", UA["User-Agent"], "-ss", str(start), "-i", info["preview"],
         "-t", str(limit), "-ac", "2", "-ar", "44100", "-c:a", "pcm_f32le", str(tmp)])
    tmp.rename(dest)
    return dest


def join(paths, dest):
    if len(paths) == 1:
        run(["ffmpeg", "-y", "-v", "error", "-i", str(paths[0]), "-c:a", "pcm_f32le", str(dest)])
        return
    durations = [duration_of(p) for p in paths]
    inputs, chain, label = [], [], "[0]"
    for p in paths:
        inputs += ["-i", str(p)]
    for i in range(1, len(paths)):
        fade = min(JOIN_FADE, durations[i - 1] / 3, durations[i] / 3)
        out = f"[j{i}]"
        chain.append(f"{label}[{i}]acrossfade=d={fade:.3f}:c1=qsin:c2=qsin{out}")
        label = out
    run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(chain), "-map", label,
         "-c:a", "pcm_f32le", str(dest)])


def make_loop(src, dest):
    """Crossfades the tail into the head so the file loops without a seam (equal-power curves)."""
    total = duration_of(src)
    fade = min(LOOP_FADE, total / 4)
    loop_len = total - fade
    graph = (
        f"[0]asplit=3[a][b][c];"
        f"[a]atrim=end={fade},asetpts=PTS-STARTPTS,afade=t=in:d={fade}:curve=qsin[head];"
        f"[b]atrim=start={loop_len},asetpts=PTS-STARTPTS,afade=t=out:d={fade}:curve=qsin[tail];"
        f"[head][tail]amix=inputs=2:normalize=0:duration=first[seam];"
        f"[c]atrim=start={fade}:end={loop_len},asetpts=PTS-STARTPTS[body];"
        f"[seam][body]concat=n=2:v=0:a=1[out]"
    )
    run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-filter_complex", graph, "-map", "[out]",
         "-c:a", "pcm_f32le", str(dest)])


def encode(src, dest):
    """Gain to the loudness target; a limiter catches peaks, but never by more than MAX_LIMITING_DB."""
    log = run(["ffmpeg", "-v", "info", "-i", str(src), "-af", "loudnorm=print_format=json", "-f", "null", "-"])
    stats = json.loads(log[log.rindex("{"):log.rindex("}") + 1])
    gain = min(TARGET_LUFS - float(stats["input_i"]), MAX_TRUE_PEAK - float(stats["input_tp"]) + MAX_LIMITING_DB)
    limit = 10 ** (MAX_TRUE_PEAK / 20)
    chain = f"volume={gain:.2f}dB,alimiter=limit={limit:.3f}:attack=2:release=60:level=false"
    run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-af", chain,
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-map_metadata", "-1", "-f", "mp4", str(dest)])


def generate_noise(color, dest):
    left = f"anoisesrc=color={color}:seed=1:amplitude=0.5:duration={NOISE_SECONDS}:sample_rate=44100"
    right = f"anoisesrc=color={color}:seed=2:amplitude=0.5:duration={NOISE_SECONDS}:sample_rate=44100"
    run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", left, "-f", "lavfi", "-i", right,
         "-filter_complex", "[0][1]join=inputs=2:channel_layout=stereo[out]", "-map", "[out]",
         "-c:a", "pcm_f32le", str(dest)])


def build(key, spec, work):
    joined, looped = work / f"{key}-joined.wav", work / f"{key}-loop.wav"
    if "generate" in spec:
        generate_noise(spec["generate"], joined)
        credit = {"generated": f"{spec['generate'].capitalize()} noise, generated with FFmpeg"}
    else:
        sources = spec["sources"]
        per_source = min(MAX_PER_SOURCE, max(45, MAX_TOTAL / len(sources)))
        infos, paths = [], []
        for user, sound_id in sources:
            info = source_info(user, sound_id)
            paths.append(download(info, sound_id, per_source))
            infos.append({k: info[k] for k in ("title", "author", "url", "license", "licenseUrl")})
        join(paths, joined)
        credit = {"sources": infos}
    make_loop(joined, looped)
    encode(looped, OUT / f"{key}.mp4")
    print(f"{key}: {duration_of(OUT / f'{key}.mp4'):.0f}s", flush=True)
    return credit


def main():
    manifest = {k: v for k, v in json.loads((ROOT / "tools" / "sounds.json").read_text()).items()
                if not k.startswith("_")}
    keys = sys.argv[1:] or list(manifest)
    OUT.mkdir(exist_ok=True)
    work = ROOT / ".cache" / "work"
    work.mkdir(parents=True, exist_ok=True)
    credits_path = OUT / "credits.json"
    credits = json.loads(credits_path.read_text()) if credits_path.exists() else {}
    for key in keys:
        credits[key] = build(key, manifest[key], work)
        credits_path.write_text(json.dumps(credits, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
