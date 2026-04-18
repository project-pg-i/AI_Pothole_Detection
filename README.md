# AI Pothole Detection System
### Edge-to-Cloud Road Anomaly Detection & Mapping

<p align="center">
  <img src="https://img.shields.io/badge/Status-Active-success?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue?style=for-the-badge&logo=flutter" />
  <img src="https://img.shields.io/badge/Edge%20AI-TensorFlow%20Lite-orange?style=for-the-badge&logo=tensorflow" />
  <img src="https://img.shields.io/badge/Cloud%20AI-YOLOv8%20Medium-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/GPU-CUDA%2012.x-green?style=for-the-badge&logo=nvidia" />
</p>

---

## 📌 Overview

Manual road surveying is slow, expensive, and inconsistent. This project replaces it with a **Hybrid Edge-to-Cloud AI pipeline** that detects, geolocates, and maps road potholes in real-time using a vehicle-mounted smartphone.

A two-stage verification system minimizes false positives and cellular bandwidth usage — the smartphone handles the initial filtering, and a GPU-accelerated cloud server performs final validation before logging the hazard to a persistent geospatial database.

> Built for municipal authorities who need accurate, up-to-date road hazard maps for maintenance planning.

---

## Architecture: Two-Stage Verification

```
📱 Mobile App (Edge)                    ☁️ Flask Server (Cloud)
┌───────────────────────┐               ┌──────────────────────────┐
│  Camera Feed          │               │  Receive flagged frame   │
│         ↓             │               │           ↓              │
│  TFLite Model         │  ── HTTP ──►  │  YOLOv8 Medium (GPU)     │
│  (Local Inference)    │               │           ↓              │
│         ↓             │               │  Validate / Reject FP    │
│  Confidence > 40%?    │               │           ↓              │
│  YES → Send to cloud  │               │  Save to database.json   │
└───────────────────────┘               └──────────────────────────┘
```

### Phase 1 — Edge Computing (The Filter)
The Flutter app (`pothole_hunter`) runs a lightweight **TensorFlow Lite** model directly on the device. Only frames with a pothole confidence score **> 40%** are transmitted to the server — drastically reducing cellular data usage.

### Phase 2 — Cloud Computing (The Validator)
The Python backend (`Pothole_Server`) receives flagged frames via a secure **Ngrok tunnel** and processes them with a **YOLOv8 Medium** model on an NVIDIA RTX GPU. It rejects false positives (shadows, manhole covers, road markings) and saves verified anomalies with GPS coordinates to a persistent JSON database.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Mobile Framework** | Flutter (Dart) |
| **Edge AI** | TensorFlow Lite (`tflite_flutter`) |
| **Mapping (Client)** | `flutter_map` + OpenStreetMap |
| **Hardware** | `camera`, `geolocator` plugins |
| **Backend Language** | Python 3.x |
| **Web Framework** | Flask (WSGI) |
| **Cloud AI** | Ultralytics YOLOv8 (PyTorch + CUDA 12.x) |
| **Database** | Self-healing JSON (`database.json`) |
| **Tunneling** | Ngrok (secure HTTP tunnel) |

---

## 📂 Repository Structure

```
AI_Pothole_Detection/
│
├── pothole_hunter/          # Flutter mobile application
│   ├── lib/                 # Dart UI logic and screens
│   └── assets/              # TFLite model weights & label files
│
└── Pothole_Server/          # Python Flask backend
    ├── server.py            # API endpoints + YOLOv8 inference
    ├── best.pt              # Custom-trained YOLOv8 Medium weights
    └── database.json        # Persistent geospatial hazard database
```

---

## 🚀 Getting Started

### Prerequisites
- Python 3.8+ with pip
- Flutter SDK (stable channel)
- NVIDIA GPU with CUDA 12.x (for server-side inference)
- [Ngrok](https://ngrok.com/) account & CLI

---

### 1. Start the Cloud Server

```bash
# Navigate to the server directory
cd Pothole_Server

# Create and activate a virtual environment
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate

# Install dependencies
pip install flask werkzeug ultralytics torch torchvision

# Run the server
python server.py
```

> **Expose to the internet:** In a separate terminal, run:
> ```bash
> ngrok http 5000
> ```
> Copy the generated Ngrok URL and update it in the Flutter app config.

---

### 2. Launch the Mobile App

```bash
# Navigate to the Flutter app directory
cd pothole_hunter

# Fetch all dependencies
flutter pub get

# Run on a connected physical device
flutter run
```

> ⚠️ A **physical device** is required for real camera feed and GPS access. Emulators will not work for live detection.

---

## 📊 Features

| Feature | Description |
|---|---|
| 🗺️ **Real-Time Geolocation** | Verified potholes are automatically tagged with precise lat/lng coordinates |
| 📍 **Live Map Dashboard** | Interactive OpenStreetMap markers update dynamically as detections come in |
| 💾 **Persistent Memory** | Database survives server reboots; a cleanup script removes ghost entries on startup |
| 🔒 **Tunnel Security Bypass** | Custom request headers handle Ngrok browser warnings for seamless image rendering |
| ⚡ **Bandwidth Optimization** | Edge filtering eliminates ~60%+ of redundant network traffic before cloud processing |

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

---

## 📄 License

This project is open source. See the [LICENSE](LICENSE) file for details.
