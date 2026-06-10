import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum CameraCaptureType { documentFront, documentBack, selfie }

class CustomCameraScreen extends StatefulWidget {
  final CameraCaptureType captureType;

  const CustomCameraScreen({super.key, required this.captureType});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    // On web, the native camera plugin doesn't work.
    // Use image_picker which delegates to the browser's camera/file API.
    if (kIsWeb) {
      await _pickImageWeb();
      return;
    }

    // Native (Android/iOS) — use the camera plugin for custom viewfinder
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception("Nenhuma câmera encontrada no dispositivo.");
      }

      final isSelfie = widget.captureType == CameraCaptureType.selfie;
      final lensDirection = isSelfie ? CameraLensDirection.front : CameraLensDirection.back;
      
      CameraDescription? selectedCamera;
      try {
        selectedCamera = _cameras.firstWhere((c) => c.lensDirection == lensDirection);
      } catch (_) {
        selectedCamera = _cameras.first;
      }

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // Reduzido de high para evitar OOM Crash
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Erro ao inicializar câmera: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao acessar a câmera.')),
        );
      }
    }
  }

  /// Web fallback: open image_picker which uses browser camera or file chooser
  Future<void> _pickImageWeb() async {
    try {
      final picker = ImagePicker();
      final isSelfie = widget.captureType == CameraCaptureType.selfie;

      final picked = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: isSelfie ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (picked != null && mounted) {
        Navigator.of(context).pop(picked.path);
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint("Erro ao acessar câmera (web): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Câmera não disponível. Tente usar o upload de arquivo.'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final image = await _controller!.takePicture();
      setState(() {
        _capturedImage = image;
      });
    } catch (e) {
      debugPrint("Erro ao capturar foto: $e");
    }
  }

  void _retakePicture() {
    setState(() {
      _capturedImage = null;
    });
  }

  void _confirmPicture() {
    if (_capturedImage != null) {
      Navigator.of(context).pop(_capturedImage!.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // On web, we show a loading spinner while image_picker opens
    if (kIsWeb) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_capturedImage != null) {
      return _buildPreviewConfirmation();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview
          CameraPreview(_controller!),
          
          // Visual Overlay Guide (Mold)
          _buildCameraOverlay(),

          // Instructions Text
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Text(
              _getInstructionText(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4),
                ],
              ),
            ),
          ),

          // Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                ),
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 48), 
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPreviewConfirmation() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: kIsWeb
                  ? Image.network(
                      _capturedImage!.path,
                      fit: BoxFit.contain,
                    )
                  : Image.file(
                      File(_capturedImage!.path),
                      fit: BoxFit.contain,
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              color: Colors.black87,
              child: Column(
                children: [
                  const Text(
                    "A foto ficou nítida?",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _retakePicture,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text("Tirar Outra", style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _confirmPicture,
                        icon: const Icon(Icons.check),
                        label: const Text("Confirmar"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  String _getInstructionText() {
    switch (widget.captureType) {
      case CameraCaptureType.documentFront:
        return "Alinhe a FRENTE do documento\ndentro do retângulo";
      case CameraCaptureType.documentBack:
        return "Alinhe o VERSO do documento\ndentro do retângulo";
      case CameraCaptureType.selfie:
        return "Posicione seu rosto\ndentro do círculo";
    }
  }

  Widget _buildCameraOverlay() {
    final isSelfie = widget.captureType == CameraCaptureType.selfie;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.7),
        BlendMode.srcOut,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              height: isSelfie ? 350 : 250,
              width: isSelfie ? 300 : 350,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isSelfie ? 150 : 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
