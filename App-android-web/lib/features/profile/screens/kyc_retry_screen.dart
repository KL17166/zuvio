import 'dart:io' as io show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:katari/providers/auth_provider.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/features/camera/screens/custom_camera_screen.dart';

class KycRetryScreen extends StatefulWidget {
  const KycRetryScreen({super.key});

  @override
  State<KycRetryScreen> createState() => _KycRetryScreenState();
}

class _KycRetryScreenState extends State<KycRetryScreen> {
  XFile? _docFront;
  XFile? _docBack;
  XFile? _selfie;
  bool _isPickingImage = false;
  bool _isUploading = false;

  Future<void> _captureImage(String type) async {
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);

    try {
      if (kIsWeb) {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null && mounted) {
          setState(() {
            if (type == 'front') _docFront = image;
            if (type == 'back') _docBack = image;
            if (type == 'selfie') _selfie = image;
          });
        }
      } else {
        if (!mounted) return;
        final XFile? image = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(
            builder: (_) => CustomCameraScreen(
              captureType: type == 'front'
                  ? CameraCaptureType.documentFront
                  : type == 'back'
                      ? CameraCaptureType.documentBack
                      : CameraCaptureType.selfie,
            ),
          ),
        );

        if (image != null && mounted) {
          setState(() {
            if (type == 'front') _docFront = image;
            if (type == 'back') _docBack = image;
            if (type == 'selfie') _selfie = image;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _submitDocuments() async {
    if (_docFront == null || _docBack == null || _selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, tire todas as três fotos.')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final auth = context.read<AuthProvider>();
      auth.updateDocuments(
        front: _docFront?.path,
        back: _docBack?.path,
        selfie: _selfie?.path,
      );

      await auth.uploadDocuments();
      
      // Update local state to SUBMITTED directly since backend does it
      auth.updateKycInfo('SUBMITTED', null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documentos enviados com sucesso! Em análise.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back to payment screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao enviar documentos. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reenvio de Documentos'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Documentos Recusados',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.kycRejectReason ?? 'Seus documentos enviados anteriormente não puderam ser validados. Por favor, envie fotos legíveis novamente.',
                    style: TextStyle(color: Colors.red.shade900),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildImagePickerRow('Frente do RG/CNH', _docFront, () => _captureImage('front')),
            const SizedBox(height: 16),
            _buildImagePickerRow('Verso do RG/CNH', _docBack, () => _captureImage('back')),
            const SizedBox(height: 16),
            _buildImagePickerRow('Selfie', _selfie, () => _captureImage('selfie')),
            
            const SizedBox(height: 48),
            _isUploading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _submitDocuments,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primaryColor,
                  ),
                  child: const Text('ENVIAR NOVAMENTE', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerRow(String title, XFile? image, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb
                          ? Image.network(image.path, fit: BoxFit.cover)
                          : Image.file(io.File(image.path), fit: BoxFit.cover),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(image != null ? 'Capturada ✓' : 'Tocar para capturar',
                      style: TextStyle(color: image != null ? Colors.green : Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Icon(image != null ? Icons.check_circle : Icons.arrow_forward_ios,
                color: image != null ? Colors.green : Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}
