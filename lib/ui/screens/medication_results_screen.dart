import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../domain/models/medication.dart';
import '../../data/repositories/medication_storage.dart';
import 'medication_cabinet_screen.dart';

class MedicationResultsScreen extends StatefulWidget {
  final String medicationName;
  final String dosage;
  final String frequency;
  final String verdict;
  final String interactionDetails;
  final bool isWarning;
  final List<String>? activeIngredients;

  const MedicationResultsScreen({
    super.key,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.verdict,
    required this.interactionDetails,
    this.isWarning = false,
    this.activeIngredients,
  });

  @override
  State<MedicationResultsScreen> createState() => _MedicationResultsScreenState();
}

class _MedicationResultsScreenState extends State<MedicationResultsScreen> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interaction Results', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent.shade400,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Results for ${widget.medicationName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Data from OpenFDA • Processed by Gemma4',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade600, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isWarning ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.isWarning ? Colors.red.shade700 : Colors.green.shade700),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        widget.isWarning ? Icons.warning_rounded : Icons.check_circle_rounded,
                        color: widget.isWarning ? Colors.red.shade700 : Colors.green.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.verdict,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.isWarning ? Colors.red.shade900 : Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setState(() => _showDetails = !_showDetails),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showDetails ? Icons.expand_less : Icons.expand_more,
                            color: widget.isWarning ? Colors.red.shade800 : Colors.green.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showDetails ? 'Show less' : 'Learn more',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: widget.isWarning ? Colors.red.shade800 : Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showDetails) ...[
                    const SizedBox(height: 8),
                    Divider(color: widget.isWarning ? Colors.red.shade200 : Colors.green.shade200),
                    const SizedBox(height: 8),
                    MarkdownBody(
                      data: widget.interactionDetails,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 15,
                          color: widget.isWarning ? Colors.red.shade900 : Colors.green.shade900,
                          height: 1.5,
                        ),
                        listBullet: TextStyle(
                          color: widget.isWarning ? Colors.red.shade900 : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                // Save to cabinet logic
                final storage = MedicationStorage();
                final meds = await storage.getMedications();
                meds.add(Medication(
                  name: widget.medicationName,
                  dosage: widget.dosage,
                  frequency: widget.frequency,
                  dateAdded: DateTime.now().toIso8601String(),
                  activeIngredients: widget.activeIngredients,
                ));
                await storage.saveMedications(meds);
                
                if (!context.mounted) return;
                // Pop back to the cabinet screen
                Navigator.pushAndRemoveUntil(
                  context, 
                  MaterialPageRoute(builder: (_) => const MedicationCabinetScreen()), 
                  (route) => route.isFirst
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save to Cabinet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
