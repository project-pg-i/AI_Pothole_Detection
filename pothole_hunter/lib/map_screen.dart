import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  final String serverUrl; // e.g., https://xxxx.ngrok-free.app/upload
  const MapScreen({super.key, required this.serverUrl});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // --- CONTROLLERS & STATE ---
  final MapController _mapController = MapController();
  List<Marker> _potholeMarkers = [];
  LatLng? _myLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _locateMe();      // 1. Find User immediately
    _fetchPotholes(); // 2. Load Potholes from Server
  }

  // --- 1. USER LOCATION LOGIC (The Blue Dot) ---
  Future<void> _locateMe() async {
    try {
      // Check/Request Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // Get precise location
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      if (!mounted) return;

      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
      });

      // FLY TO USER (Auto-Focus)
      // We use a slight delay to ensure the map is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _mapController.move(_myLocation!, 16.0); // Zoom level 16 is good for streets
      });

      print("📍 User found at: ${pos.latitude}, ${pos.longitude}");

    } catch (e) {
      print("GPS Error: $e");
    }
  }

  // --- 2. FETCH DATA LOGIC ---
  Future<void> _fetchPotholes() async {
    // Clean the URL (remove '/upload' to get the base domain)
    final baseUrl = widget.serverUrl.replaceAll("/upload", "");
    
    try {
      print("🌍 Fetching from: $baseUrl/get_potholes");
      final response = await http.get(Uri.parse("$baseUrl/get_potholes"));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print("✅ Potholes Found: ${data.length}");
        _createMarkers(data, baseUrl);
      } else {
        print("❌ Server Error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Network Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 3. MARKER CREATION ---
  void _createMarkers(List<dynamic> potholes, String baseUrl) {
    List<Marker> newMarkers = [];

    for (var p in potholes) {
      // URL Logic: Combine Base URL + Relative Path from DB
      // Server sends: "uploads/123.jpg"
      // We make: "https://ngrok.app/uploads/123.jpg"
      String relativePath = p['image_url'];
      
      // Safety check if DB has old full URLs
      if (relativePath.startsWith("http")) {
        relativePath = "uploads/${relativePath.split('/').last}";
      }

      // Remove leading slash if present to avoid double slash
      if (relativePath.startsWith("/")) {
        relativePath = relativePath.substring(1);
      }

      String cleanImageUrl = "$baseUrl/$relativePath";
      
      // Create the Marker
      newMarkers.add(
        Marker(
          width: 60.0,
          height: 60.0,
          point: LatLng(
            double.parse(p['lat'].toString()), 
            double.parse(p['long'].toString())
          ),
          child: GestureDetector(
            onTap: () => _showEvidence(context, cleanImageUrl, p['date'] ?? "Unknown"),
            child: Column(
              children: [
                // The Visual Icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 2),
                    boxShadow: [const BoxShadow(blurRadius: 4, color: Colors.black45)]
                  ),
                  child: const Text("🕳️", style: TextStyle(fontSize: 22)),
                ),
                // Little arrow pointing down
                const Icon(Icons.arrow_drop_down, color: Colors.red, size: 24)
              ],
            ),
          ),
        ),
      );
    }
    setState(() => _potholeMarkers = newMarkers);
  }

  // --- 4. POPUP VIEWER (With 403 Fix) ---
  void _showEvidence(BuildContext context, String imageUrl, String time) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(15)
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Text(
                  "Detected: $time", 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              
              // Image
              ClipRRect(
                child: Image.network(
                  imageUrl,
                  // 👇 CRITICAL: Allows image to bypass Ngrok warning
                  headers: const {"ngrok-skip-browser-warning": "true"},
                  loadingBuilder: (c, child, p) => p == null 
                      ? child 
                      : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  errorBuilder: (c, e, s) => Container(
                    height: 150,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                        Text("Image missing from server", style: TextStyle(color: Colors.grey[600]))
                      ],
                    ),
                  ),
                ),
              ),
              
              // Close Button
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("CLOSE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Map")),
      
      // Button to re-center on User
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        child: const Icon(Icons.my_location, color: Colors.white),
        onPressed: () {
          if (_myLocation != null) {
            _mapController.move(_myLocation!, 16.0);
          } else {
            _locateMe(); // Try finding location again
          }
        },
      ),

      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _myLocation ?? const LatLng(20.5937, 78.9629), 
          initialZoom: 5.0,
          onMapReady: () {
            if (_myLocation != null) {
              _mapController.move(_myLocation!, 16.0);
            }
          },
        ),
        children: [
          // 1. Map Tiles (OpenStreetMap)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.pothole.hunter',
          ),

          // 2. Pothole Markers (Layer 1)
          MarkerLayer(markers: _potholeMarkers),

          // 3. User Location Marker (Layer 2 - The Blue Dot)
          if (_myLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _myLocation!,
                  width: 25,
                  height: 25,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [const BoxShadow(blurRadius: 5, color: Colors.black26)]
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}