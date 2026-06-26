import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/selected_allergens.dart';
import '../../data/repositories/llm_repository.dart';
import 'explanation_screen.dart';

class AllergenResultScreen extends ConsumerStatefulWidget {
  final String? barcode;
  final SelectedAllergens selectedAllergens;
  final String? productName;
  final String? ingredientsText;
  final String? translatedText;
  final bool wasTranslated;
  final bool offFound;

  const AllergenResultScreen({
    super.key,
    this.barcode,
    required this.selectedAllergens,
    this.productName,
    this.ingredientsText,
    this.translatedText,
    this.wasTranslated = false,
    this.offFound = false,
  });

  @override
  ConsumerState<AllergenResultScreen> createState() => _AllergenResultScreenState();
}

class _AllergenResultScreenState extends ConsumerState<AllergenResultScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _hasSpoken = false;
  
  Set<String> _matches = {};
  String _allergensListStr = "";
  
  String? _generatedExplanation;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _analyzeAndGenerate();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }

  void _analyzeAndGenerate() {
    String detectSource = (widget.translatedText != null && widget.translatedText!.isNotEmpty) 
        ? widget.translatedText! 
        : (widget.ingredientsText ?? "");

    _matches = widget.selectedAllergens.findMatchesInText(detectSource);
    _allergensListStr = _matches.join(", ");

    if (_matches.isNotEmpty) {
      _speakWarning();
      _generateExplanation(detectSource);
    }
  }

  void _speakWarning() async {
    if (_hasSpoken) return;
    _hasSpoken = true;

    String productName = (widget.productName != null && widget.productName!.trim().isNotEmpty) 
        ? widget.productName!.trim() 
        : "this item";

    String speakMsg = "Hey there, allergen $_allergensListStr detected in $productName.";
    await _tts.speak(speakMsg);
  }

  Future<void> _generateExplanation(String usedText) async {
    setState(() {
      _isGenerating = true;
    });

    final llmRepo = ref.read(llmRepositoryProvider);
    llmRepo.setModel('gemma3:4b');

    String prompt = "Ingredients: \"$usedText\"\n\n"
        "Detected allergens: $_allergensListStr\n\n"
        "Write a concise consumer-friendly explanation in EXACTLY three sections:\n"
        "Section 1: Why the food will cause allergy\n"
        "Section 2: What is the allergic reaction\n"
        "Section 3: What to do if accidentally consumed\n\n"
        "Rules:\n"
        "- In Section 1, name specific ingredients that contain the allergens and why.\n"
        "- In Section 2, list common reactions from mild to severe.\n"
        "- In Section 3, give step-by-step actions with each step on a new line, including when to seek medical attention.\n"
        "- IMPORTANT: This is for Malaysia - use emergency number 999 (NOT 911).\n"
        "- Keep sentences short; avoid extra preface or conclusion; return only the three sections.";

    try {
      String explanation = await llmRepo.generate(prompt);
      if (mounted) {
        setState(() {
          _generatedExplanation = explanation.trim();
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Widget _buildCard(String title, Widget content, {Color borderColor = const Color(0xFFFF6F00)}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.label_important, color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSafe = _matches.isEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Result'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barcode and Product Name
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scanned Barcode', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(widget.barcode ?? 'N/A', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    if (widget.productName != null) ...[
                      const SizedBox(height: 8),
                      Text(widget.productName!, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isSafe ? Colors.green.shade700 : Colors.red.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    isSafe ? 'SAFE' : 'WARNING: $_allergensListStr',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildCard('Selected Allergens', 
                Text(
                  widget.selectedAllergens.isEmpty ? "None selected" : widget.selectedAllergens.toDisplayString(),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),

              _buildCard('Ingredients (OCR)', 
                Text(
                  (widget.wasTranslated && widget.translatedText != null)
                      ? "Original:\n${widget.ingredientsText ?? ''}\n\nEnglish (translated):\n${widget.translatedText}"
                      : (widget.ingredientsText ?? "(no ingredients provided)"),
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                borderColor: Colors.grey.shade800
              ),

              if (!isSafe)
                _buildCard('Matched Allergens', 
                  Text(
                    _allergensListStr,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  borderColor: const Color(0xFFFF6F00)
                ),

              if (!isSafe)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      if (_generatedExplanation != null) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ExplanationScreen(
                            explanation: _generatedExplanation!,
                            productName: widget.productName,
                            allergens: _allergensListStr,
                          )
                        ));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing details...')));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6F00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: _isGenerating 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('LEARN MORE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}
