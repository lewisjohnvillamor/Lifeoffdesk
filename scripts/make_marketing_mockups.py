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
    'recap': ('m8-recap.png', 'Every adventure, counted', 'New streets, places passed and time, computed on your phone.',
              'iOS Simulator · sample adventure'),
    'card': ('m7-card-sticker.png', 'Make it a memory', 'Turn an adventure into a card to share.',
             'iOS Simulator · sample adventure'),
    'help': ('m9-help-chat-emergency.png', 'Help, even offline', 'Ask in Taglish. The AI finds the right first-aid card; 911 comes first.',
             'iOS Simulator · keyword routing (no AI in Simulator) · cards from NHS, St John Ambulance, WHO, The AA'),
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


# ---------- App Store-style panels: realistic phones, tilted pairs, bleeding off the bottom ----------

def real_phone(screen, width):
    """Titanium-look frame with black rim and a Dynamic Island, `width` px wide (RGBA, unrotated)."""
    sw = int(width * 0.9)
    sh = int(screen.height * sw / screen.width)
    screen = screen.convert('RGB').resize((sw, sh), Image.LANCZOS)
    rim = int(width * 0.022)              # black glass border
    metal = (width - sw) // 2 - rim       # titanium band
    w, h = width, sh + 2 * (rim + metal)
    radius = int(width * 0.16)
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    # Metal band: vertical gradient, light to darker silver.
    band = Image.new('RGBA', (w, h))
    bd = ImageDraw.Draw(band)
    for y in range(h):
        t = y / h
        c = int(226 - 50 * abs(0.5 - t) * 2)
        bd.line([(0, y), (w, y)], fill=(c, c + 2, c + 5, 255))
    img.paste(band, (0, 0), rounded_mask((w, h), radius))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], radius, outline=(150, 154, 160, 255), width=2)
    d.rounded_rectangle([metal, metal, w - metal - 1, h - metal - 1], radius - metal, fill=(12, 14, 13, 255))
    img.paste(screen, (metal + rim, metal + rim), rounded_mask((sw, sh), radius - metal - rim))
    island_w, island_h = int(sw * 0.3), int(sw * 0.085)
    top = metal + rim + int(sw * 0.03)
    d.rounded_rectangle([(w - island_w) // 2, top, (w + island_w) // 2, top + island_h], island_h // 2, fill=(0, 0, 0, 255))
    # Side buttons.
    for y0, y1 in ((0.22, 0.27), (0.31, 0.39)):
        d.rounded_rectangle([0, int(h * y0), 4, int(h * y1)], 2, fill=(170, 174, 180, 255))
    d.rounded_rectangle([w - 4, int(h * 0.28), w, int(h * 0.38)], 2, fill=(170, 174, 180, 255))
    return img

def place(canvas, phone_img, center_x, top, angle=0):
    """Rotate and paste with a soft shadow; parts below the canvas are simply cropped (bleed)."""
    rotated = phone_img.rotate(angle, resample=Image.BICUBIC, expand=True)
    shadow = Image.new('RGBA', rotated.size, (0, 0, 0, 0))
    shadow.putalpha(rotated.getchannel('A').point(lambda a: int(a * 0.28)))
    blur = max(8, rotated.width // 30)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    x = int(center_x - rotated.width / 2)
    canvas.alpha_composite(shadow, (x + blur // 2, top + blur)) if x + blur // 2 >= 0 else None
    paste_clipped(canvas, rotated, x, top)

def paste_clipped(canvas, img, x, y):
    left, upper = max(0, -x), max(0, -y)
    right, lower = min(img.width, canvas.width - x), min(img.height, canvas.height - y)
    if right > left and lower > upper:
        canvas.alpha_composite(img.crop((left, upper, right, lower)), (x + left, y + upper))

def hero_panel(screens, headline, badge, size=(1290, 1500)):
    W, H = size
    img = Image.new('RGBA', size, '#FFFFFF')
    d = ImageDraw.Draw(img)
    hf = font('Bold', int(W * 0.074))
    y = int(H * 0.07)
    for line in headline.split('\n'):
        d.text((int(W * 0.07), y), line, font=hf, fill=INK); y += int(hf.size * 1.08)
    bf = font('Bold', int(W * 0.026))
    bx, by = int(W * 0.07), y + int(H * 0.02)
    d.rounded_rectangle([bx, by, bx + int(d.textlength(badge, font=bf)) + 40, by + int(bf.size * 1.9)], 18, fill=PRIMARY)
    d.text((bx + 20, by + int(bf.size * 0.45)), badge, font=bf, fill='#FFFFFF')
    back = real_phone(screens[1], int(W * 0.42))
    front = real_phone(screens[0], int(W * 0.42))
    place(img, back, int(W * 0.76), int(H * 0.17), angle=-12)
    place(img, front, int(W * 0.36), int(H * 0.40), angle=10)
    return img.convert('RGB')

def feature_panel(screen, title, subtitle, size=(1290, 1500), angle=0):
    W, H = size
    img = Image.new('RGBA', size, '#FFFFFF')
    d = ImageDraw.Draw(img)
    tf, sf = font('Bold', int(W * 0.07)), font('Regular', int(W * 0.04))
    d.text((W / 2, int(H * 0.07)), title, font=tf, fill=INK, anchor='ma')
    y = int(H * 0.07 + tf.size * 1.35)
    for line in subtitle.split('\n'):
        d.text((W / 2, y), line, font=sf, fill=SECONDARY, anchor='ma'); y += int(sf.size * 1.3)
    place(img, real_phone(screen, int(W * 0.62)), W // 2, y + int(H * 0.05), angle=angle)
    return img.convert('RGB')

STORE = [  # (kind, screens, title, subtitle)
    ('hero', ['m2-demo-closeup.png', 'iphone-coach.png'], 'Your world\ngrows offline', 'On-device AI · no cloud'),
    ('feature', ['iphone-coach.png'], 'AI that notices', 'On-device Qwen3\nnudges you outside'),
    ('feature', ['m6-route.png'], 'Go somewhere new', 'Real places, offline routes\non mapped streets'),
    ('feature', ['m1-demo-tilted.png'], 'Fog becomes paper', 'Every street you explore\nis inked in'),
    ('feature', ['m8-recap.png'], 'Every adventure, counted', 'New streets and places,\ncomputed on your phone'),
    ('feature', ['m9-help-chat-emergency.png'], 'Help, even offline', 'First aid and road trouble,\n911 first when it matters'),
    ('feature', ['m7-card-sticker.png'], 'Keep the memory', 'Turn an adventure\ninto a card'),
]

def store_set(shots, out):
    panels = []
    for i, (kind, files, title, sub) in enumerate(STORE):
        paths = [shots / f for f in files]
        if not all(p.exists() for p in paths):
            print('skip store panel (missing)', files); continue
        screens = [Image.open(p) for p in paths]
        panel = hero_panel(screens, title, sub) if kind == 'hero' else feature_panel(screens[0], title, sub)
        path = out / f'store-{i + 1}.jpg'
        panel.save(path, quality=90)
        panels.append(panel)
        print('wrote', path)
    if panels:
        gap = 24
        strip_img = Image.new('RGB', (sum(p.width for p in panels) + gap * (len(panels) + 1), panels[0].height + 2 * gap), '#EEF0EC')
        x = gap
        for p in panels:
            strip_img.paste(p, (x, gap)); x += p.width + gap
        strip_img.thumbnail((4000, 4000), Image.LANCZOS)
        strip_img.save(out / 'store-strip.jpg', quality=88)
        print('wrote', out / 'store-strip.jpg')

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
    store_set(args.shots, args.out)

if __name__ == '__main__':
    main()
