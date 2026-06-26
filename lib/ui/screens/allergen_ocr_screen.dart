import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../domain/models/selected_allergens.dart';
import '../../data/repositories/llm_repository.dart';
import 'allergen_result_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AllergenOcrScreen extends ConsumerStatefulWidget {
  final SelectedAllergens selectedAllergens;

  const AllergenOcrScreen({super.key, required this.selectedAllergens});

  @override
  ConsumerState<AllergenOcrScreen> createState() => _AllergenOcrScreenState();
}

class _AllergenOcrScreenState extends ConsumerState<AllergenOcrScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  bool _isProcessing = false;

  Future<void> _captureAndOcr() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    setState(() {
      _imagePath = photo.path;
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer();
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      String ingredients = recognizedText.text.trim();
      if (ingredients.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No text found')));
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Translate to English
      final llmRepo = ref.read(llmRepositoryProvider);
      llmRepo.setModel('gemma3:4b');
      
      String prompt = "Detect the source language and translate the following food ingredients to English. "
          "If already English, lightly normalize spacing and casing. Return only the translation.\n\n"
          "$ingredients";

      String translatedText = await llmRepo.generate(prompt);
      String translatedClean = translatedText.trim();
      if (translatedClean.isEmpty) translatedClean = ingredients;
      
      bool wasTranslated = translatedClean.toLowerCase() != ingredients.toLowerCase();

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => AllergenResultScreen(
          barcode: "",
          selectedAllergens: widget.selectedAllergens,
          ingredientsText: ingredients,
          translatedText: translatedClean,
          wasTranslated: wasTranslated,
        )
      ));

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR Error: $e')));
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('OCR Ingredients'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFF6F00), width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_imagePath != null)
                        Image.asset(_imagePath!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                      else
                        const Center(
                          child: Text(
                            'Capture ingredients label',
                            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        ),
                      if (_isProcessing)
                        const CircularProgressIndicator(color: Color(0xFFFF6F00)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _captureAndOcr,
                  icon: const Icon(Icons.document_scanner, color: Colors.black),
                  label: const Text('CAPTURE & OCR', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F00),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
