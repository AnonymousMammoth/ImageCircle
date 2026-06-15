#!/usr/bin/env python3
"""Generate ImageCircle app icons (main, dark, tinted) at 1024x1024."""

from PIL import Image, ImageDraw, ImageFont
import os

SIZE = 1024
RED = (255, 59, 48, 255)          # iOS-style red
DARK_RED = (180, 30, 30, 255)      # Dark mode red
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial.ttf"
OUT_DIR = "ImageCircle/Assets.xcassets/AppIcon.appiconset"


def make_main():
    img = Image.new("RGBA", (SIZE, SIZE), RED)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, 420)
    draw.text((SIZE // 2, SIZE // 2 + 10), "IC", font=font, fill=WHITE, anchor="mm")
    return img.convert("RGB")


def make_dark():
    img = Image.new("RGBA", (SIZE, SIZE), DARK_RED)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, 420)
    draw.text((SIZE // 2, SIZE // 2 + 10), "IC", font=font, fill=WHITE, anchor="mm")
    return img.convert("RGB")


def make_tinted():
    # Tinted icons should be grayscale with the icon shape opaque and text cut out.
    # White circle on transparent background with "IC" punched out.
    img = Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    margin = 12
    draw.ellipse([margin, margin, SIZE - margin, SIZE - margin], fill=WHITE)

    font = ImageFont.truetype(FONT_PATH, 420)
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.text((SIZE // 2, SIZE // 2 + 10), "IC", font=font, fill=255, anchor="mm")

    # Where the mask is opaque, make the image transparent (punch out text).
    erased = Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)
    result = Image.composite(erased, img, mask)
    return result


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    make_main().save(os.path.join(OUT_DIR, "AppIcon.png"))
    make_dark().save(os.path.join(OUT_DIR, "AppIcon-dark.png"))
    make_tinted().save(os.path.join(OUT_DIR, "AppIcon-tinted.png"))
    print("Generated app icons:")
    for name in ("AppIcon.png", "AppIcon-dark.png", "AppIcon-tinted.png"):
        path = os.path.join(OUT_DIR, name)
        print(f"  {path}  ({os.path.getsize(path)} bytes)")


if __name__ == "__main__":
    main()
