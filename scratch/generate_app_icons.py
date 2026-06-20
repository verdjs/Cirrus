import os
from PIL import Image

def crop_and_resize_icon(src_path, dst_path, target_size):
    with Image.open(src_path) as img:
        source_w, source_h = img.size
        target_w, target_h = target_size
        target_aspect = float(target_w) / float(target_h)
        source_aspect = float(source_w) / float(source_h)
        
        if source_aspect > target_aspect:
            # Source is wider, crop the sides
            new_w = int(round(source_h * target_aspect))
            left = (source_w - new_w) // 2
            top = 0
            right = left + new_w
            bottom = source_h
        else:
            # Source is taller, crop top/bottom
            new_h = int(round(source_w / target_aspect))
            left = 0
            top = (source_h - new_h) // 2
            right = source_w
            bottom = top + new_h
            
        cropped = img.crop((left, top, right, bottom))
        resized = cropped.resize((target_w, target_h), Image.Resampling.LANCZOS)
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        resized.save(dst_path)
        print(f"Generated {dst_path} with size {target_size}")

def main():
    src_icon = "/Users/henry/Downloads/CloudNow-main/icon.png"
    if not os.path.exists(src_icon):
        print(f"Error: source icon not found at {src_icon}")
        return
        
    projects = ["cloudnow TV", "cloudnow Mac"]
    
    for proj in projects:
        assets_base = f"/Users/henry/Downloads/CloudNow-main/{proj}/CloudNow/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
        
        # App Icon (400x240 and 800x480)
        # Front layer
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon_400x240.png", (400, 240))
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon_800x480.png", (800, 480))
        # Back layer (identically generated to prevent visual tearing/empty borders during focus tilting)
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon.imagestack/Back.imagestacklayer/Content.imageset/bg_400x240.png", (400, 240))
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon.imagestack/Back.imagestacklayer/Content.imageset/bg_800x480.png", (800, 480))
        
        # App Icon - App Store (1280x768)
        # Front layer
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon_1280x768.png", (1280, 768))
        # Back layer
        crop_and_resize_icon(src_icon, f"{assets_base}/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/bg_1280x768.png", (1280, 768))

if __name__ == "__main__":
    main()
