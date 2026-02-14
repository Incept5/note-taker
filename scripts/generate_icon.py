#!/usr/bin/env python3
"""Generate NoteTaker app icon programmatically — shield + microphone."""

import math
from PIL import Image, ImageDraw

SIZE = 1024
PAD = 80


def make_shield_path(cx, cy, w, h):
    """Generate a classic shield shape: flat top, straight sides tapering to rounded bottom."""
    points = []
    steps = 40

    top_y = cy - h / 2
    bot_y = cy + h / 2
    top_r = w * 0.08  # small radius for top corners

    # Top-left rounded corner
    for i in range(steps // 4 + 1):
        angle = math.pi + (math.pi / 2) * (i / (steps // 4))
        px = (cx - w / 2 + top_r) + top_r * math.cos(angle)
        py = (top_y + top_r) + top_r * math.sin(angle)
        points.append((px, py))

    # Top-right rounded corner
    for i in range(steps // 4 + 1):
        angle = (3 * math.pi / 2) + (math.pi / 2) * (i / (steps // 4))
        px = (cx + w / 2 - top_r) + top_r * math.cos(angle)
        py = (top_y + top_r) + top_r * math.sin(angle)
        points.append((px, py))

    # Right side: straight for top 50%, then curves inward to bottom center
    straight_end = top_y + h * 0.50
    points.append((cx + w / 2, straight_end))

    # Curve from right side to bottom point
    for i in range(1, steps + 1):
        t = i / steps
        # Quadratic bezier: right-mid -> bottom-center
        # Control point pulls the curve outward slightly to keep it rounded
        p0 = (cx + w / 2, straight_end)          # start
        p1 = (cx + w * 0.25, straight_end + h * 0.35)  # control
        p2 = (cx, bot_y)                           # end (bottom center)

        px = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        py = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        points.append((px, py))

    # Curve from bottom point to left side (mirror)
    for i in range(1, steps + 1):
        t = i / steps
        p0 = (cx, bot_y)
        p1 = (cx - w * 0.25, straight_end + h * 0.35)
        p2 = (cx - w / 2, straight_end)

        px = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        py = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        points.append((px, py))

    # Left side straight back to top
    points.append((cx - w / 2, top_y + top_r))

    return points


def draw_microphone(draw, cx, cy, scale):
    """Draw a stylized microphone icon."""
    mic_color = (220, 250, 248)  # light mint for contrast

    # Microphone capsule (pill shape)
    cap_w = 100 * scale
    cap_h = 170 * scale
    cap_r = cap_w / 2
    cap_top = cy - cap_h * 0.45
    cap_bot = cap_top + cap_h

    draw.rounded_rectangle(
        [cx - cap_w / 2, cap_top, cx + cap_w / 2, cap_bot],
        radius=int(cap_r),
        fill=mic_color,
    )

    # Grille lines on the capsule
    line_color = (80, 170, 165)
    grille_top = cap_top + cap_h * 0.12
    grille_bot = cap_top + cap_h * 0.52
    num_lines = 5
    indent = cap_w * 0.22
    for i in range(num_lines):
        t = i / (num_lines - 1)
        ly = grille_top + (grille_bot - grille_top) * t
        draw.line(
            [(cx - cap_w / 2 + indent, ly), (cx + cap_w / 2 - indent, ly)],
            fill=line_color,
            width=max(2, int(3 * scale)),
        )

    # U-shaped cradle arc
    arc_w = cap_w * 1.7
    arc_h_val = cap_h * 0.45
    arc_y = cap_bot - cap_h * 0.22
    arc_thickness = max(4, int(12 * scale))

    draw.arc(
        [cx - arc_w / 2, arc_y, cx + arc_w / 2, arc_y + arc_h_val * 2],
        start=0,
        end=180,
        fill=mic_color,
        width=arc_thickness,
    )

    # Stand (vertical bar)
    stand_w = max(4, int(12 * scale))
    stand_top = arc_y + arc_h_val
    stand_h = 55 * scale
    draw.rounded_rectangle(
        [cx - stand_w / 2, stand_top, cx + stand_w / 2, stand_top + stand_h],
        radius=int(stand_w / 2),
        fill=mic_color,
    )

    # Base (horizontal bar)
    base_w = 90 * scale
    base_h = max(4, int(12 * scale))
    base_top = stand_top + stand_h - base_h / 3
    draw.rounded_rectangle(
        [cx - base_w / 2, base_top, cx + base_w / 2, base_top + base_h],
        radius=int(base_h / 2),
        fill=mic_color,
    )


def create_icon():
    """Create the full app icon."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background: macOS rounded square
    bg_radius = int(SIZE * 0.22)
    draw.rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1],
        radius=bg_radius,
        fill=(245, 248, 250, 255),  # very light cool gray
    )

    # Shield dimensions
    shield_w = SIZE - PAD * 2
    shield_h = shield_w * 1.05
    cx = SIZE / 2
    cy = SIZE / 2 + 10

    shield_points = make_shield_path(cx, cy, shield_w, shield_h)

    # Draw shield base color
    mid_teal = (13, 115, 119)
    draw.polygon(shield_points, fill=mid_teal)

    # Create gradient overlay (lighter at top, darker at bottom)
    gradient_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gradient_draw = ImageDraw.Draw(gradient_img)

    shield_top = cy - shield_h / 2
    shield_bot = cy + shield_h / 2

    # Top highlight
    for i in range(int(shield_h * 0.45)):
        t = 1 - (i / (shield_h * 0.45))
        alpha = int(45 * t)
        y = shield_top + i
        gradient_draw.line([(0, y), (SIZE, y)], fill=(255, 255, 255, alpha))

    # Bottom darkening
    for i in range(int(shield_h * 0.35)):
        t = i / (shield_h * 0.35)
        alpha = int(35 * t)
        y = shield_bot - int(shield_h * 0.35) + i
        gradient_draw.line([(0, y), (SIZE, y)], fill=(0, 0, 0, alpha))

    # Mask gradient to shield shape
    mask_img = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask_img)
    mask_draw.polygon(shield_points, fill=255)

    gradient_img.putalpha(
        Image.composite(gradient_img.split()[3], Image.new("L", (SIZE, SIZE), 0), mask_img)
    )
    img = Image.alpha_composite(img, gradient_img)

    # Draw microphone on the composited image
    draw = ImageDraw.Draw(img)
    mic_scale = shield_w / 820
    draw_microphone(draw, cx, cy - 10, mic_scale)

    return img


def generate_sizes(source_img, output_dir):
    """Generate all required macOS icon sizes from the 1024px source."""
    import json

    sizes = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    images_json = []

    for size, scale in sizes:
        pixel_size = size * scale
        resized = source_img.resize((pixel_size, pixel_size), Image.LANCZOS)
        filename = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        filepath = f"{output_dir}/{filename}"
        resized.save(filepath, format="PNG")
        print(f"  Created {filename} ({pixel_size}x{pixel_size}px)")

        images_json.append({
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{size}x{size}",
        })

    # Write Contents.json
    contents = {
        "images": images_json,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }

    contents_path = f"{output_dir}/Contents.json"
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"  Updated {contents_path}")


if __name__ == "__main__":
    import os

    print("Generating NoteTaker app icon...")
    icon = create_icon()

    # Save 1024px master
    build_dir = os.path.join(os.path.dirname(__file__), "..", "build")
    os.makedirs(build_dir, exist_ok=True)
    master_path = os.path.join(build_dir, "app_icon_1024.png")
    icon.save(master_path, format="PNG")
    print(f"Master icon: {master_path}")

    # Generate all sizes into the asset catalog
    appiconset = os.path.join(
        os.path.dirname(__file__), "..", "Assets.xcassets", "AppIcon.appiconset"
    )
    print(f"\nGenerating icon sizes for {appiconset}:")
    generate_sizes(icon, appiconset)

    print("\nDone! App icon is ready.")
