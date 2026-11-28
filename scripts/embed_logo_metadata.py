#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, PngImagePlugin

ROOT = Path(__file__).resolve().parents[1]
LOGO = ROOT / 'assets' / 'logo' / 'cineflow_logo.png'
ICON = ROOT / 'assets' / 'logo' / 'cineflow_icon.png'
SRC = Path('/home/aqeel-gill/Downloads/image_ebb07ba2.jpg')
META = {
    'Title': 'CineFlow Studio',
    'Author': 'Aqeel Gill',
    'Copyright': 'Copyright (c) 2026 Aqeel Gill - CineFlow Studio',
    'Contact': '+92 3202080379',
    'Software': 'CineFlow Studio Universal Downloader',
}

def save_png(im, path: Path):
    info = PngImagePlugin.PngInfo()
    for k, v in META.items():
        info.add_text(k, v)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format='PNG', pnginfo=info)

def main():
    img = Image.open(SRC).convert('RGBA')
    w, h = img.size
    s = min(w, h)
    left = (w - s) // 2
    top = (h - s) // 2
    icon = img.crop((left, top, left + s, top + s)).resize((512, 512), Image.LANCZOS)
    save_png(img, LOGO)
    save_png(icon, ICON)
    for p in [LOGO, ICON]:
        info = Image.open(p).info
        print(p)
        for k in META:
            print(f'  {k}: {info.get(k)}')

if __name__ == '__main__':
    main()
