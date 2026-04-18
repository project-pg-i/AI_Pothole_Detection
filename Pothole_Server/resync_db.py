import os
import json
import time

UPLOAD_FOLDER = 'uploads'
DB_FILE = 'database.json'

# 1. Get list of all images
if not os.path.exists(UPLOAD_FOLDER):
    print("No uploads folder found!")
    exit()

files = [f for f in os.listdir(UPLOAD_FOLDER) if f.endswith(('.jpg', '.png', '.jpeg'))]
print(f"Found {len(files)} images in folder.")

# 2. Rebuild Database entries
new_db = []
for filename in files:
    
    entry = {
        "id": filename,
        "lat": 23.0225,
        "long": 72.5714, 
        "image_url": f"uploads/{filename}",
        "severity": "Medium",
        "date": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    new_db.append(entry)

# 3. Save to database.json
with open(DB_FILE, 'w') as f:
    json.dump(new_db, f, indent=4)

print(f"SUCCESS: Restored {len(new_db)} potholes to database.json")
print("Now restart your server!")