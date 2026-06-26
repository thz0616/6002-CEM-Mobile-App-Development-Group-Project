import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../domain/models/selected_allergens.dart';
import '../../data/repositories/off_repository.dart';
import 'allergen_ocr_screen.dart';
import 'allergen_result_screen.dart';

class AllergenScannerScreen extends StatefulWidget {
  final SelectedAllergens selectedAllergens;

  const AllergenScannerScreen({super.key, required this.selectedAllergens});

  @override
  State<AllergenScannerScreen> createState() => _AllergenScannerScreenState();
}

class _AllergenScannerScreenState extends State<AllergenScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  
  bool _hasScanned = false;
  bool _isFetching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_hasScanned || _isFetching) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    
    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.length < 8) return;

    setState(() {
      _hasScanned = true;
      _isFetching = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanned: $rawValue'), duration: const Duration(seconds: 1)));

    try {
      final data = await OffRepository.instance.fetchByBarcode(rawValue);
      if (!mounted) return;

      if (data.found && data.ingredients != null && data.ingredients!.isNotEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => AllergenResultScreen(
            barcode: data.code ?? rawValue,
            selectedAllergens: widget.selectedAllergens,
            productName: data.name,
            ingredientsText: data.ingredients,
            offFound: true,
          )
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product not found in OFF. Please OCR ingredients.')));
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => AllergenOcrScreen(selectedAllergens: widget.selectedAllergens)
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OFF lookup failed. Please OCR ingredients.')));
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => AllergenOcrScreen(selectedAllergens: widget.selectedAllergens)
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Custom overlay to match Android screen
          Positioned.fill(
            child: Container(
              decoration: ShapeDecoration(
                shape: _ScannerOverlayShape(
                  borderColor: Colors.white,
                  borderWidth: 2,
                  overlayColor: Colors.black54,
                ),
              ),
            ),
          ),
          Positioned(
            top: 48,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Row(
                children: [
                  const Icon(Icons.center_focus_weak, color: Color(0xFFFF6F00), size: 32),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Align the barcode within the rectangle', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
          if (_isFetching)
            const Center(child: CircularProgressIndicator(color: Color(0xFFFF6F00))),
        ],
      ),
    );
  }
}

class _ScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;

  const _ScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 1.0,
    this.overlayColor = const Color(0x88000000),
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10.0);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path _getClip(Size size) {
      Path path = Path();
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      
      final width = size.width * 0.8;
      final height = size.height * 0.3;
      final left = (size.width - width) / 2;
      final top = (size.height - height) / 2;
      
      path.addRect(Rect.fromLTWH(left, top, width, height));
      return path;
    }
    return _getClip(rect.size)..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width * 0.8;
    final height = rect.height * 0.3;
    final left = (rect.width - width) / 2;
    final top = (rect.height - height) / 2;
    
    final backgroundPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;
      
    final boxRect = Rect.fromLTWH(left, top, width, height);
    
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
      
    final backgroundPath = Path()
      ..addRect(rect)
      ..addRect(boxRect)
      ..fillType = PathFillType.evenOdd;
      
    canvas.drawPath(backgroundPath, backgroundPaint);
    canvas.drawRect(boxRect, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return _ScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
    );
  }
}
