import os
import time
import json
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename
from ultralytics import YOLO
import torch

# --- CONFIGURATION ---
UPLOAD_FOLDER = 'uploads'
DB_FILE = 'database.json'
MODEL_PATH = 'best.pt' 
CONFIDENCE_THRESHOLD = 0.75
PORT = 5000

# --- SETUP ---
app = Flask(__name__)
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

# --- DATABASE---
def load_db():
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, 'r') as f:
                return json.load(f)
        except:
            return []
    return []

def save_db(data):
    with open(DB_FILE, 'w') as f:
        json.dump(data, f, indent=4)

def clean_ghost_entries(data):
    """Removes map markers if the image file was deleted manually"""
    valid_data = []
    removed_count = 0
    
    for entry in data:
        # Check if the file actually exists in 'uploads/' folder
        # entry['image_url'] looks like "uploads/123.jpg" or just "123.jpg"
        filename = os.path.basename(entry['image_url'])
        file_path = os.path.join(UPLOAD_FOLDER, filename)
        
        if os.path.exists(file_path):
            valid_data.append(entry)
        else:
            removed_count += 1
            
    if removed_count > 0:
        print(f"Auto-Clean: Removed {removed_count} ghost entries (File missing).")
        save_db(valid_data) 
        
    return valid_data

# 1. Load DB
raw_db = load_db()
# 2. Clean DB 
potholes_db = clean_ghost_entries(raw_db)
print(f"Database Loaded: {len(potholes_db)} valid potholes.")

# --- LOAD MODEL ---
print("INITIALIZING GPU...")
try:
    model = YOLO(MODEL_PATH)
    print(f"Model loaded on: {torch.cuda.get_device_name(0)}")
except Exception as e:
    print(f"CRITICAL ERROR: Could not load model. {e}")
    exit()

@app.route('/upload', methods=['POST'])
def upload_pothole():
    if 'image' not in request.files:
        return jsonify({"error": "No image part"}), 400
    
    file = request.files['image']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    filename = secure_filename(f"{int(time.time())}_{file.filename}")
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    file.save(filepath)

    print(f"Analyzing {filename}...")
    start_time = time.time()
    
    # Run Inference
    results = model(filepath, conf=0.15, device='cpu', verbose=False)
    
    pothole_found = False
    max_conf = 0.0

    for result in results:
        for box in result.boxes:
            conf = float(box.conf[0])
            cls = int(box.cls[0])
            class_name = model.names[cls]
            
            print(f"    Model Saw: '{class_name}' with {int(conf*100)}% confidence")

            if conf > CONFIDENCE_THRESHOLD:
                pothole_found = True
                max_conf = conf

    inference_time = (time.time() - start_time) * 1000
    print(f"    Speed: {inference_time:.2f}ms")

    if pothole_found:
        lat = request.form.get('lat', '0.0')
        long = request.form.get('long', '0.0')
        
        image_url = f"uploads/{filename}" 
        
        new_pothole = {
            "id": filename,
            "lat": float(lat),
            "long": float(long),
            "image_url": image_url,
            "severity": "High" if max_conf > 0.7 else "Medium",
            "date": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        
        potholes_db.append(new_pothole)
        save_db(potholes_db)
        
        print(" VERIFIED & SAVED to database.json")
        return jsonify({"status": "verified", "data": new_pothole}), 200
    else:
        print(" REJECTED. Deleting file.")
        try:
            os.remove(filepath)
        except:
            pass
        return jsonify({"status": "rejected", "reason": "Not a pothole"}), 200

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(UPLOAD_FOLDER, filename)

@app.route('/get_potholes', methods=['GET'])
def get_potholes():
    return jsonify(potholes_db)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT, debug=False)