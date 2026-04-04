"""Convert pos.png to proper multi-size ICO."""
from PIL import Image
import struct
import io
import os

src_path = r"D:\Download\pos.png"
ico_path = r"C:\Users\Mageed\Desktop\FlutterProject\Lamsa-main\windows\runner\resources\app_icon.ico"
png_path = r"C:\Users\Mageed\Desktop\FlutterProject\Lamsa-main\assets\app_icon.png"

# Load source
src = Image.open(src_path).convert("RGBA")
print(f"Source: {src.size}")

# Copy PNG to assets
src.save(png_path, "PNG")

# Build ICO manually for proper multi-size support
sizes = [16, 24, 32, 48, 64, 128, 256]

def png_bytes(img, size):
    resized = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    resized.save(buf, format="PNG")
    return buf.getvalue()

# ICO header: 2 bytes reserved, 2 bytes type (1=ICO), 2 bytes count
entries = []
data_blobs = []

for s in sizes:
    blob = png_bytes(src, s)
    data_blobs.append(blob)
    # ICO directory entry: width, height, colors, reserved, planes, bpp, size, offset
    w = s if s < 256 else 0  # 0 means 256
    h = s if s < 256 else 0
    entries.append((w, h, 0, 0, 1, 32, len(blob)))

# Calculate offsets: header=6, each entry=16
header_size = 6 + len(entries) * 16
offset = header_size

ico_data = io.BytesIO()
# Header
ico_data.write(struct.pack("<HHH", 0, 1, len(entries)))
# Directory entries
for i, (w, h, colors, reserved, planes, bpp, blob_size) in enumerate(entries):
    ico_data.write(struct.pack("<BBBBHHII", w, h, colors, reserved, planes, bpp, blob_size, offset))
    offset += blob_size
# Image data
for blob in data_blobs:
    ico_data.write(blob)

with open(ico_path, "wb") as f:
    f.write(ico_data.getvalue())

file_size = os.path.getsize(ico_path)
print(f"ICO saved: {ico_path}")
print(f"ICO file size: {file_size:,} bytes")
print(f"Contains {len(sizes)} sizes: {sizes}")

# Verify
verify = Image.open(ico_path)
print(f"Verify - sizes in ICO: {verify.info.get('sizes', 'unknown')}")
print("Done!")
