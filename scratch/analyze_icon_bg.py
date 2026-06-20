from PIL import Image
from collections import Counter

icon_path = "/Users/henry/Downloads/CloudNow-main/icon.png"
try:
    with Image.open(icon_path) as img:
        width, height = img.size
        # Collect colors from the outer edge (top, bottom, left, right)
        edge_pixels = []
        for x in range(width):
            edge_pixels.append(img.getpixel((x, 0)))
            edge_pixels.append(img.getpixel((x, height - 1)))
        for y in range(height):
            edge_pixels.append(img.getpixel((0, y)))
            edge_pixels.append(img.getpixel((width - 1, y)))
        
        counter = Counter(edge_pixels)
        most_common = counter.most_common(5)
        print("Most common colors on the edges:")
        for color, count in most_common:
            percentage = (count / len(edge_pixels)) * 100
            print(f"Color: {color}, Count: {count} ({percentage:.2f}%)")
except Exception as e:
    print(f"Error: {e}")
