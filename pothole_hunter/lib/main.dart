import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart'; // <--- NEW IMPORT
import 'map_screen.dart';

// --- CONFIGURATION ---
const String SERVER_URL = "https://giggly-uninfatuated-kenley.ngrok-free.dev/upload"; 

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Camera Error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const PotholeHunterScreen(),
    );
  }
}

class PotholeHunterScreen extends StatefulWidget {
  const PotholeHunterScreen({super.key});
  @override
  State<PotholeHunterScreen> createState() => _PotholeHunterScreenState();
}

class _PotholeHunterScreenState extends State<PotholeHunterScreen> {
  // --- STATE ---
  bool _isPatrolling = false;
  String _camType = "Phone"; 
  String _networkUrl = "rtsp://192.168.0.1/live"; 
  String _status = "Ready";
  
  // Flashlight State
  FlashMode _currentFlashMode = FlashMode.auto; // Default

  // Controllers
  CameraController? _phoneController;
  VlcPlayerController? _netController;
  Interpreter? _interpreter;
  Timer? _timer;
  DateTime? _lastUploadTime;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadFlashPreference(); // <--- Load saved setting on startup
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/pothole_model.tflite');
      setState(() => _status = "AI Ready");
    } catch (e) {
      setState(() => _status = "AI Error: $e");
    }
  }

  // --- PREFERENCE LOGIC ---
  Future<void> _loadFlashPreference() async {
    final prefs = await SharedPreferences.getInstance();
    String? mode = prefs.getString('flash_mode');
    if (mode != null) {
      setState(() {
        if (mode == 'auto') _currentFlashMode = FlashMode.auto;
        if (mode == 'always') _currentFlashMode = FlashMode.always; // 'always' = ON
        if (mode == 'off') _currentFlashMode = FlashMode.off;
      });
    }
  }

  Future<void> _saveFlashPreference(FlashMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String modeStr = 'auto';
    if (mode == FlashMode.always) modeStr = 'always';
    if (mode == FlashMode.off) modeStr = 'off';
    await prefs.setString('flash_mode', modeStr);
    setState(() => _currentFlashMode = mode);
  }

  // --- CAMERA SWITCHING LOGIC ---
  Future<void> _initializeCamera() async {
    await _phoneController?.dispose();
    await _netController?.dispose();
    _phoneController = null;
    _netController = null;

    if (_camType == "Phone" && cameras.isNotEmpty) {
      _phoneController = CameraController(cameras[0], ResolutionPreset.medium);
      await _phoneController!.initialize();
      // Apply Flash Mode after initialization
      await _phoneController!.setFlashMode(_currentFlashMode);
    } else if (_camType == "Network") {
      _netController = VlcPlayerController.network(
        _networkUrl,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );
    }
    setState(() {});
  }

  // --- START/STOP LOGIC ---
  void _handleStartButton() {
    if (_isPatrolling) {
      _stopPatrol();
    } else {
      // If using Phone, ask for Flashlight mode first
      if (_camType == "Phone") {
        _showFlashDialog();
      } else {
        _startPatrol();
      }
    }
  }

  void _showFlashDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Select Flashlight Mode"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _flashOption("Auto", FlashMode.auto, Icons.flash_auto),
              _flashOption("On (Always)", FlashMode.always, Icons.flash_on),
              _flashOption("Off", FlashMode.off, Icons.flash_off),
            ],
          ),
        );
      },
    );
  }

  Widget _flashOption(String label, FlashMode mode, IconData icon) {
    bool isSelected = _currentFlashMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.yellow : Colors.white),
      title: Text(label, style: TextStyle(color: isSelected ? Colors.yellow : Colors.white)),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.yellow) : null,
      onTap: () {
        _saveFlashPreference(mode); // Save setting
        Navigator.pop(context); // Close dialog
        _startPatrol(); // Start the patrol
      },
    );
  }

  void _startPatrol() async {
    setState(() => _status = "Starting $_camType Camera...");
    await _initializeCamera();
    
    setState(() {
      _isPatrolling = true;
      _status = "Scanning Road...";
    });

    _timer = Timer.periodic(const Duration(seconds: 2), (t) => _captureAndAnalyze());
  }

  void _stopPatrol() async {
    _timer?.cancel();
    await _phoneController?.dispose();
    await _netController?.dispose();
    setState(() {
      _isPatrolling = false;
      _phoneController = null;
      _netController = null;
      _status = "Patrol Stopped";
    });
  }

  // --- THE BRAIN ---
  Future<void> _captureAndAnalyze() async {
    if (_lastUploadTime != null && DateTime.now().difference(_lastUploadTime!) < const Duration(seconds: 5)) {
      return; 
    }

    try {
      String? imagePath;

      if (_camType == "Phone" && _phoneController != null && _phoneController!.value.isInitialized) {
        final file = await _phoneController!.takePicture();
        imagePath = file.path;
      } 
      else if (_camType == "Network" && _netController != null) {
        imagePath = null; 
      }

      if (imagePath != null) {
        bool found = await _runInference(imagePath);
        
        if (found) {
          setState(() => _status = "🚨 Pothole! Getting GPS...");
          Position? pos = await _determinePosition();

          if (pos != null) {
            setState(() => _status = "📍 GPS Locked. Uploading...");
            await _uploadEvidence(imagePath, pos);
            _lastUploadTime = DateTime.now();
          } else {
            setState(() => _status = "⚠️ GPS Failed (Go Outside)");
          }
        } else {
          setState(() => _status = "Road Clear");
        }
      }
    } catch (e) {
      setState(() => _status = "Loop Error: $e");
    }
  }

  Future<bool> _runInference(String imagePath) async {
    if (_interpreter == null) return false;

    try {
      final imageData = File(imagePath).readAsBytesSync();
      final image = img.decodeImage(imageData);
      if (image == null) return false;

      final resized = img.copyResize(image, width: 640, height: 640);

      var input = List.generate(1, (i) => 
        List.generate(640, (y) => 
          List.generate(640, (x) {
            var pixel = resized.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          })
        )
      );

      var output = List.filled(1 * 5 * 8400, 0.0).reshape([1, 5, 8400]);

      _interpreter!.run(input, output);

      double maxConfidence = 0.0;
      for (int i = 0; i < 8400; i++) {
        double confidence = output[0][4][i];
        if (confidence > maxConfidence) maxConfidence = confidence;
      }

      print("🤖 AI Confidence: ${(maxConfidence * 100).toStringAsFixed(1)}%");
      return maxConfidence > 0.40;

    } catch (e) {
      print("AI Error: $e");
      return false;
    }
  }

  Future<void> _uploadEvidence(String path, Position pos) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(SERVER_URL));
      request.fields['lat'] = pos.latitude.toString();
      request.fields['long'] = pos.longitude.toString();
      request.files.add(await http.MultipartFile.fromPath('image', path));
      
      var response = await request.send();
      
      if (response.statusCode == 200) {
        setState(() => _status = "✅ Uploaded Successfully!");
      } else {
        setState(() => _status = "❌ Server Reject: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _status = "⚠️ Net Error: $e");
    }
  }

  Future<Position?> _determinePosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, 
        timeLimit: const Duration(seconds: 5)
      );
    } catch (e) {
      print("GPS Error: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pothole Hunter Pro")),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _isPatrolling
                    ? (_camType == "Phone"
                        ? (_phoneController != null ? CameraPreview(_phoneController!) : const CircularProgressIndicator())
                        : (_netController != null 
                            ? VlcPlayer(controller: _netController!, aspectRatio: 16/9, placeholder: const Text("Connecting...")) 
                            : const CircularProgressIndicator()))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.security, size: 60, color: Colors.grey),
                          const SizedBox(height: 20),
                          const Text("System Standby", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(10)),
                            child: DropdownButton<String>(
                              value: _camType,
                              dropdownColor: Colors.grey[800],
                              underline: Container(),
                              items: const [
                                DropdownMenuItem(value: "Phone", child: Text("📱 Phone Camera")),
                                DropdownMenuItem(value: "Network", child: Text("📡 External (Drone/Dashcam)")),
                              ],
                              onChanged: (val) => setState(() => _camType = val!),
                            ),
                          ),
                          if (_camType == "Network")
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: TextField(
                                onChanged: (v) => _networkUrl = v,
                                decoration: const InputDecoration(
                                  labelText: "RTSP Stream URL",
                                  hintText: "rtsp://192.168.x.x/live",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black87,
            child: Column(
              children: [
                Text(_status, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: "monospace")),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleStartButton, // <--- CHANGED THIS
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isPatrolling ? Colors.red : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: Text(_isPatrolling ? "STOP PATROL" : "START PATROL"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton(
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.map),
                      onPressed: () {
                         if(_isPatrolling) _stopPatrol();
                         Navigator.push(context, MaterialPageRoute(builder: (c) => MapScreen(serverUrl: SERVER_URL)));
                      },
                    )
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}