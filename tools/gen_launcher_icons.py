#!/usr/bin/env python3
"""ساخت آیکون لانچر اندروید از نشان سپر خود برنامه.

قبلاً APK با آیکون پیش‌فرض Flutter منتشر می‌شد (آیکون، لوگوی فلاتر بود) چون
هیچ mipmap‌ای در ریپو نبود و `flutter create` پیش‌فرض‌ها را می‌گذاشت.
این اسکریپت همان مسیر SVG موجود (`app/assets/tiles/ic_glyph_shield_check.svg`)
را روی یک پس‌زمینهٔ تیره می‌کشد و در `android-extra/res/mipmap-*/ic_launcher.png`
می‌نویسد؛ مرحلهٔ «Install Android widget resources» در CI این پوشه را روی
منابع اندروید کپی می‌کند، پس آیکون خودکار جای پیش‌فرض را می‌گیرد.

اجرا:  python3 tools/gen_launcher_icons.py
نیاز:  pip install pillow
"""
import os

from PIL import Image, ImageDraw

SS = 4  # supersampling
SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

BG_TOP = (13, 20, 32)      # #0D1420
BG_BOTTOM = (8, 12, 20)    # #080C14
SHIELD = (61, 207, 154)    # #3DCF9A — اکسنت برنامه
SHIELD_GLOW = (61, 207, 154, 46)


def bezier(p0, p1, p2, p3, steps=90):
    out = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = (mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0]
             + t**3 * p3[0])
        y = (mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1]
             + t**3 * p3[1])
        out.append((x, y))
    return out


def shield_outline():
    """همان مسیر SVG: M12 3 L19 5.8 v5 c0 4.6 -3 8.3 -7 10.2 c-4 -1.9 -7 -5.6 -7 -10.2 v-5 z"""
    pts = [(12, 3), (19, 5.8), (19, 10.8)]
    pts += bezier((19, 10.8), (19, 15.4), (16, 19.1), (12, 21))
    pts += bezier((12, 21), (8, 19.1), (5, 15.4), (5, 10.8))
    pts += [(5, 5.8), (12, 3)]
    return pts


def check_outline():
    """m8.8 12 l2.3 2.3 l4.2 -4.6"""
    return [(8.8, 12), (11.1, 14.3), (15.3, 9.7)]


def stroke(draw, pts, width, color, scale, offset, radius):
    """خط با سرِ گرد: مهره‌زدن دایره روی نقاط نمونه‌برداری‌شده."""
    r = width / 2 * scale
    for x, y in pts:
        cx = offset + x * scale
        cy = offset + y * scale
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    # پوشش پیوستهٔ مرکزی
    for i in range(len(pts) - 1):
        x0 = offset + pts[i][0] * scale
        y0 = offset + pts[i][1] * scale
        x1 = offset + pts[i + 1][0] * scale
        y1 = offset + pts[i + 1][1] * scale
        draw.line((x0, y0, x1, y1), fill=color, width=int(round(r * 2)))
    return radius


def render(size):
    canvas = size * SS
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    # پس‌زمینهٔ گرادیانی داخل یک مربع گردگوشه (اندروید خودش ماسک می‌کند)
    bg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    grad = Image.new("RGB", (1, canvas))
    for y in range(canvas):
        t = y / max(canvas - 1, 1)
        grad.putpixel((0, y), tuple(
            int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
        ))
    grad = grad.resize((canvas, canvas))
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, canvas - 1, canvas - 1), radius=int(canvas * 0.22), fill=255
    )
    bg.paste(grad, (0, 0), mask)
    img = Image.alpha_composite(img, bg)

    # هالهٔ ملایم پشت سپر
    glow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (canvas * 0.12, canvas * 0.10, canvas * 0.88, canvas * 0.92),
        fill=SHIELD_GLOW,
    )
    glow = glow.filter(ImageFilter_Gaussian(canvas * 0.06))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img)
    # viewBox 24 → 58% از عرض
    scale = canvas * 0.58 / 24
    offset = (canvas - 24 * scale) / 2
    d_stroke_w = 1.9
    stroke(d, shield_outline(), d_stroke_w, SHIELD, scale, offset, 0)
    stroke(d, check_outline(), d_stroke_w, SHIELD, scale, offset, 0)

    return img.resize((size, size), Image.LANCZOS)


def ImageFilter_Gaussian(r):
    from PIL import ImageFilter
    return ImageFilter.GaussianBlur(r)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(root, "android-extra", "res")
    for density, size in SIZES.items():
        out_dir = os.path.join(base, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "ic_launcher.png")
        render(size).save(path, optimize=True)
        print(f"{path}  ({size}x{size})")


if __name__ == "__main__":
    main()
