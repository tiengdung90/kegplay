#!/usr/bin/env python3
"""Tạo biểu tượng tạm cho Kegplay → app/Kegplay.icns (chỉ người phát triển chạy; cần Pillow + iconutil).
Thay bằng thiết kế riêng: đặt PNG 1024×1024 vào app/icon-1024.png rồi chạy lại với tham số --from-png."""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "app", "icon-1024.png")

def draw():
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # nền bo góc kiểu macOS, chuyển màu đỏ rượu vang
    grad = Image.new("RGBA", (S, S))
    gp = grad.load()
    for y in range(S):
        t = y / (S - 1)
        r, g, b = int(150 - 70 * t), int(28 - 14 * t), int(48 - 20 * t)
        for x in range(S):
            gp[x, y] = (r, g, b, 255)
    mask = Image.new("L", (S, S), 0)
    m = 100
    ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], radius=185, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # thùng gỗ (keg) cách điệu: thân bầu + 2 đai
    cx, cy, w, h = S // 2, S // 2 + 6, 430, 520
    wood = (236, 196, 130, 255)
    d.rounded_rectangle([cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2], radius=150, fill=wood)
    band = (92, 58, 30, 255)
    for dy in (-150, 150):
        d.rounded_rectangle([cx - w // 2 - 8, cy + dy - 22, cx + w // 2 + 8, cy + dy + 22], radius=20, fill=band)
    # nút "play" ở giữa thùng
    tri = [(cx - 62, cy - 92), (cx - 62, cy + 92), (cx + 96, cy)]
    d.polygon(tri, fill=(120, 24, 40, 255))
    return img

def main():
    if "--from-png" in sys.argv and os.path.exists(SRC):
        img = Image.open(SRC).convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    else:
        img = draw()
        img.save(SRC)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "Kegplay.iconset")
        os.makedirs(iconset)
        for size in (16, 32, 128, 256, 512):
            img.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
            img.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
        out = os.path.join(ROOT, "app", "Kegplay.icns")
        subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", out])
        print("==>", out)

if __name__ == "__main__":
    main()
