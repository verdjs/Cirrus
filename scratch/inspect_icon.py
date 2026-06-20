import os
from PIL import Image

icon_path = "/Users/henry/Downloads/CloudNow-main/icon.png"
if os.path.exists(icon_path):
    with Image.open(icon_path) as img:
        print(f"Format: {img.format}")
        print(f"Size: {img.size}")
        print(f"Mode: {img.mode}")
        has_alpha = 'A' in img.mode or (img.mode == 'P' and 'transparency' in img.info)
        print(f"Has Alpha/Transparency: {has_alpha}")
else:
    print(f"Icon not found at {icon_path}")
