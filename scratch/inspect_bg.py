from PIL import Image

bg_path = "/Users/henry/Downloads/CloudNow-main/cloudnow TV/CloudNow/Assets.xcassets/App Icon & Top Shelf Image.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/bg_400x240.png"
try:
    with Image.open(bg_path) as img:
        print(f"Format: {img.format}, Size: {img.size}, Mode: {img.mode}")
        colors = img.getcolors(maxcolors=100000)
        if colors:
            print(f"Number of unique colors in background: {len(colors)}")
            if len(colors) <= 5:
                print("Unique colors:")
                for count, color in colors:
                    print(f"Color: {color}, Count: {count}")
        else:
            print("More than 100000 unique colors")
except Exception as e:
    print(f"Error: {e}")
