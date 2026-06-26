import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../data/repositories/open_food_facts_repository.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final barcode = barcodes.first.rawValue!;
      
      setState(() {
        _isProcessing = true;
      });

      try {
        final offRepo = ref.read(openFoodFactsRepositoryProvider);
        final productData = await offRepo.fetchByBarcode(barcode);
        
        if (!mounted) return;
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Product Found'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Code: ${productData.code}'),
                  const SizedBox(height: 8),
                  Text('Name: ${productData.name ?? 'Unknown'}'),
                  const SizedBox(height: 8),
                  Text('Ingredients: ${productData.ingredients ?? 'None listed'}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _isProcessing = false;
                  });
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR & Barcode Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _handleBarcode,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          // Simple scanner overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final picker = ImagePicker();
          final XFile? image = await picker.pickImage(source: ImageSource.camera);
          if (image != null) {
            setState(() {
              _isProcessing = true;
            });
            try {
              final textRecognizer = TextRecognizer();
              final inputImage = InputImage.fromFilePath(image.path);
              final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
              await textRecognizer.close();
              
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('OCR Result'),
                  content: SingleChildScrollView(
                    child: Text(recognizedText.text),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            } finally {
              if (mounted) {
                setState(() {
                  _isProcessing = false;
                });
              }
            }
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
