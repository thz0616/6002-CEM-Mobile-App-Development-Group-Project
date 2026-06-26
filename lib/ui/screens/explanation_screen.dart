import 'package:flutter/material.dart';

class ExplanationScreen extends StatelessWidget {
  final String explanation;
  final String? productName;
  final String? allergens;

  const ExplanationScreen({
    super.key,
    required this.explanation,
    this.productName,
    this.allergens,
  });

  String _formatForDisplay(String text) {
    String t = text.trim();
    t = t.replaceAll('\r\n', '\n');
    t = t.replaceAllMapped(RegExp(r'(^|[^\n])\s*(\d+\.)\s+'), (match) {
      String prefix = match.group(1)!;
      return '$prefix\n    ${match.group(2)} ';
    });
    t = t.replaceAllMapped(RegExp(r'(^|[^\n])\s*[•\-]\s+'), (match) {
      String prefix = match.group(1)!;
      return '$prefix\n    • ';
    });
    t = t.replaceAllMapped(RegExp(r'^(Section\s*[123]:.*)$', multiLine: true, caseSensitive: false), (match) => '${match.group(1)}\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t;
  }

  @override
  Widget build(BuildContext context) {
    String titleText = (productName != null && productName!.isNotEmpty) 
        ? "Analysis: $productName" 
        : "Allergen Analysis";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFFF6F00),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (allergens != null && allergens!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '⚠ $allergens',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      )
                    ]
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.grey, width: 4),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    _formatForDisplay(explanation),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C1E0A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF6F00).withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6F00)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Disclaimer: This is not medical advice. For emergencies or severe reactions, seek professional medical help immediately.",
                          style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
