#!/usr/bin/env python3
"""Diz que cores tem cada wallpaper de uma pasta, para o filtro por cor.

Uso: colors.py PASTA CACHE.json

Lê o que faltar (ou mudou) com o ImageMagick, guarda no CACHE e escreve na
saída um JSON {nome do arquivo: [cores]}. As cores são: red, orange, yellow,
green, teal, blue, purple, pink, dark, light, gray. Um wallpaper tem a cor
dominante, a segunda se ela pesa quase tanto, e dark/light quando o fundo é
escuro ou claro.
"""
import colorsys
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

EXT = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".jxl", ".avif", ".heif")
HUES = [  # (até que matiz, em graus, nome)
    (15, "red"), (45, "orange"), (70, "yellow"), (165, "green"),
    (200, "teal"), (255, "blue"), (300, "purple"), (345, "pink"), (361, "red"),
]
SIZE = 48


def hue_name(h):
    deg = h * 360
    for limit, name in HUES:
        if deg < limit:
            return name
    return "red"


def analyse(path):
    try:
        raw = subprocess.run(
            ["magick", "-define", f"jpeg:size={SIZE * 2}x{SIZE * 2}", path + "[0]",
             "-resize", f"{SIZE}x{SIZE}!", "-depth", "8", "rgb:-"],
            capture_output=True, timeout=90, env={**os.environ, "MAGICK_THREAD_LIMIT": "1"},
        ).stdout
    except (subprocess.TimeoutExpired, OSError):
        return []
    n = len(raw) // 3
    if n == 0:
        return []
    weight = {}
    colored = dark = light = 0
    for i in range(n):
        r, g, b = raw[3 * i] / 255, raw[3 * i + 1] / 255, raw[3 * i + 2] / 255
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if v < 0.2:
            dark += 1
        elif s < 0.15:
            if v > 0.8:
                light += 1
        else:
            colored += 1
            name = hue_name(h)
            weight[name] = weight.get(name, 0) + s * v
    out = []
    ranked = sorted(weight.items(), key=lambda kv: -kv[1])
    if ranked and colored >= 0.15 * n:
        out.append(ranked[0][0])
        if len(ranked) > 1 and ranked[1][1] >= 0.6 * ranked[0][1]:
            out.append(ranked[1][0])
    if dark / n > 0.5:
        out.append("dark")
    if light / n > 0.4:
        out.append("light")
    return out or ["gray"]


def main():
    folder, cache_path = sys.argv[1], sys.argv[2]
    try:
        with open(cache_path) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}

    files = {}
    for name in os.listdir(folder):
        if name.lower().endswith(EXT):
            try:
                files[name] = os.stat(os.path.join(folder, name)).st_mtime_ns
            except OSError:
                pass

    todo = [n for n, m in files.items() if cache.get(n, {}).get("m") != m]
    if todo:
        workers = max(2, (os.cpu_count() or 4) // 2)
        with ThreadPoolExecutor(workers) as pool:
            for name, colors in zip(todo, pool.map(lambda n: analyse(os.path.join(folder, n)), todo)):
                cache[name] = {"m": files[name], "c": colors}

    cache = {n: v for n, v in cache.items() if n in files}
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    tmp = cache_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, cache_path)
    print(json.dumps({n: v["c"] for n, v in cache.items()}))


main()
