#!/usr/bin/env python3
"""Compose marketing mockups from real app screenshots (Simulator demo world or iPhone captures).

Each output places an unedited screenshot in a simple phone frame on the brand ivory with a headline.
Screens are not retouched; demo screens keep their in-app "Demo world"/SAMPLE labels and each image
carries a small footnote saying where the screen came from.

Usage: scripts/make_marketing_mockups.py <screenshot-dir> [--out marketing/mockups]
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CANVAS, INK, PRIMARY, SECONDARY, BORDER = '#F8F6EF', '#283A31', '#46785B', '#69776D', '#D9DED4'
FONT_DIR = Path('/usr/share/fonts/opentype/inter')

# name -> (screenshot file, headline, subline, footnote)
SHOTS = {
    'map': ('m1-demo-tilted.png', 'Watch your world grow', 'Every street you explore turns from fog into paper.',
            'iOS Simulator · Demo world (sample adventures)'),
    'closeup': ('m2-demo-closeup.png', 'Your streets, inked in', 'Photos you take are pinned where you took them.',
                'iOS Simulator · Demo world (sample adventures and captures)'),
    'route': ('m6-route.png', 'Go somewhere new', 'A suggested route along mapped streets, fully offline.',
              'iOS Simulator · Makati · route on OpenStreetMap streets'),
    'me': ('m4-me-demo.png', 'Your life off desk, in numbers', 'New streets, places found, area explored.',
           'iOS Simulator · Demo world (sample adventures)'),
    'adventures': ('m5-adventures-demo.png', 'Every adventure, kept', 'Search your past walks in Taglish.',
                   'iOS Simulator · Demo world (sample adventures)'),
    'card': ('m7-card-sticker.png', 'Make it a memory', 'Turn an adventure into a card to share.',
             'iOS Simulator · sample adventure'),
    'coach': ('iphone-coach.png', 'An AI that notices', 'On-device AI nudges you when your world gets smaller.',
              'Real iPhone 12 Pro Max capture · Demo world · on-device AI'),
}

def font(weight, size):
    for name in (f'Inter-{weight}.otf', f'InterDisplay-{weight}.otf'):
        if (FONT_DIR/name).exists():
            return ImageFont.truetype(str(FONT_DIR/name), size)
    return ImageFont.load_default()

def rounded_mask(size, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0]-1, size[1]-1], radius, fill=255)
    return mask

def phone(screen, height):
    """Screenshot inside a dark bezel with rounded corners and a soft shadow (RGBA), `height` tall overall."""
    scale = height / 1.16 / screen.height
    sw, sh = int(screen.width * scale), height
    screen = screen.convert('RGB').resize((sw, sh), Image.LANCZOS)
    bezel = max(10, int(sw * 0.035))
    radius = int(sw * 0.13)
    w, h = sw + 2*bezel, sh + 2*bezel
    pad = int(h * 0.06)
    out = Image.new('RGBA', (w + 2*pad, h + 2*pad), (0, 0, 0, 0))
    shadow = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + pad//3, pad+w, pad+h + pad//3], radius + bezel, fill=(40, 58, 49, 90))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(pad//2)))
    body = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, w-1, h-1], radius + bezel, fill='#1F2723')
    body.paste(screen, (bezel, bezel), rounded_mask((sw, sh), radius))
    out.alpha_composite(body, (pad, pad))
    if out.height != height:  # exact fit, whatever the bezel/shadow arithmetic gave
        out = out.resize((int(out.width * height / out.height), height), Image.LANCZOS)
    return out

def wrap(draw, text, fnt, width):
    words, lines, line = text.split(), [], ''
    for word in words:
        trial = f'{line} {word}'.strip()
        if draw.textlength(trial, font=fnt) <= width: line = trial
        else: lines.append(line); line = word
    lines.append(line)
    return lines

def poster(screen, headline, subline, footnote, size):
    W, H = size
    img = Image.new('RGBA', size, CANVAS)
    d = ImageDraw.Draw(img)
    margin = int(W * 0.08)
    hf, sf, ff = font('Bold', int(W * 0.062)), font('Regular', int(W * 0.032)), font('Regular', int(W * 0.019))
    y = int(H * 0.06)
    for line in wrap(d, headline, hf, W - 2*margin):
        d.text((W/2, y), line, font=hf, fill=INK, anchor='ma'); y += int(hf.size * 1.15)
    y += int(sf.size * 0.4)
    for line in wrap(d, subline, sf, W - 2*margin):
        d.text((W/2, y), line, font=sf, fill=SECONDARY, anchor='ma'); y += int(sf.size * 1.3)
    foot_h = int(H * 0.06)
    device = phone(screen, H - y - foot_h)
    img.alpha_composite(device, ((W - device.width)//2, y))
    d.text((W/2, H - int(foot_h * 0.55)), footnote, font=ff, fill=SECONDARY, anchor='ma')
    return img.convert('RGB')

def strip(screens, title, footnote, size):
    """Landscape hero: three phones side by side under one headline."""
    W, H = size
    img = Image.new('RGBA', size, CANVAS)
    d = ImageDraw.Draw(img)
    hf, ff = font('Bold', int(H * 0.075)), font('Regular', int(H * 0.025))
    d.text((W/2, int(H * 0.06)), title, font=hf, fill=INK, anchor='ma')
    top = int(H * 0.06 + hf.size * 1.5)
    phones = [phone(s, H - top - int(H * 0.09)) for s in screens]
    gap = int(W * 0.02)
    total = sum(p.width for p in phones) - gap * (len(phones) - 1)
    x = (W - total)//2
    for p in phones:
        img.alpha_composite(p, (x, top)); x += p.width - gap
    d.text((W/2, H - int(H * 0.055)), footnote, font=ff, fill=SECONDARY, anchor='ma')
    return img.convert('RGB')

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('shots', type=Path)
    ap.add_argument('--out', type=Path, default=ROOT/'marketing/mockups')
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    made = []
    for name, (file, headline, subline, footnote) in SHOTS.items():
        path = args.shots/file
        if not path.exists():
            print('skip (missing)', file); continue
        screen = Image.open(path)
        for label, size in (('portrait', (1080, 1350)), ('story', (1080, 1920))):
            out = args.out/f'{name}-{label}.jpg'
            poster(screen, headline, subline, footnote, size).save(out, quality=90)
            made.append(out)
    trio = [args.shots/f for f in ('m1-demo-tilted.png', 'iphone-coach.png', 'm6-route.png')]
    if all(p.exists() for p in trio):
        out = args.out/'hero-landscape.jpg'
        strip([Image.open(p) for p in trio], 'Explore offline. Your AI stays on your phone.',
              'Screens from the app: iOS Simulator demo world and a real iPhone capture. Sample data where shown.',
              (1920, 1080)).save(out, quality=90)
        made.append(out)
    for m in made: print('wrote', m)

if __name__ == '__main__':
    main()
