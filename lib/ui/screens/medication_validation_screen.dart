import 'package:flutter/material.dart';
import 'medication_results_screen.dart';
import '../../data/repositories/medication_storage.dart';
import '../../data/services/openfda_service.dart';
import '../../data/services/llm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MedicationValidationScreen extends StatefulWidget {
  final String initialName;
  final String initialDosage;
  final String initialFrequency;

  const MedicationValidationScreen({
    Key? key,
    required this.initialName,
    required this.initialDosage,
    required this.initialFrequency,
  }) : super(key: key);

  @override
  State<MedicationValidationScreen> createState() => _MedicationValidationScreenState();
}

class _MedicationValidationScreenState extends State<MedicationValidationScreen> {
  late TextEditingController _nameController;
  late TextEditingController _dosageController;
  late TextEditingController _freqController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _dosageController = TextEditingController(text: widget.initialDosage);
    _freqController = TextEditingController(text: widget.initialFrequency);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _freqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Medication', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent.shade400,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please verify the extracted details below before checking for interactions.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              
              // Clean input fields with proper spacing and labeling
              _buildInputField(
                controller: _nameController,
                label: 'Name',
                hint: 'e.g. Aspirin',
                icon: Icons.medication_outlined,
              ),
              const SizedBox(height: 16),
              
              _buildInputField(
                controller: _dosageController,
                label: 'Dosage',
                hint: 'e.g. 500 mg',
                icon: Icons.scale_outlined,
              ),
              const SizedBox(height: 16),
              
              _buildInputField(
                controller: _freqController,
                label: 'Frequency',
                hint: 'e.g. Once daily',
                icon: Icons.access_time_outlined,
              ),
              
              const SizedBox(height: 48),
              
              // High contrast CTA button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : () async {
                    setState(() => _isLoading = true);
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      final apiKey = prefs.getString('open_fda_api_key') ?? '';
                      
                      // Load allergens
                      List<String> myAllergens = [];
                      if (prefs.getBool('peanuts') == true) myAllergens.add('Peanut');
                      if (prefs.getBool('treenuts') == true) myAllergens.add('Tree nut');
                      if (prefs.getBool('dairy') == true) myAllergens.add('Milk');
                      if (prefs.getBool('eggs') == true) myAllergens.add('Egg');
                      if (prefs.getBool('soy') == true) myAllergens.add('Soy');
                      if (prefs.getBool('wheat') == true) myAllergens.add('Wheat');
                      if (prefs.getBool('gluten') == true) myAllergens.add('Gluten');
                      if (prefs.getBool('fish') == true) myAllergens.add('Fish');
                      if (prefs.getBool('shellfish') == true) myAllergens.add('Shellfish');
                      if (prefs.getBool('sesame') == true) myAllergens.add('Sesame');
                      final otherAllergens = prefs.getString('other') ?? '';
                      if (otherAllergens.isNotEmpty) myAllergens.addAll(otherAllergens.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));

                      final storage = MedicationStorage();
                      final cabinet = await storage.getMedications();
                      final cabinetNames = cabinet.map((m) => m.name).toList();
                      final cabinetIngredients = cabinet.expand((m) => m.activeIngredients ?? <String>[]).toList();
                      final newMed = _nameController.text.trim();

                      String verdict = "No major interactions or conflicts found.";
                      String details = "Always consult a doctor before starting new medications.";
                      bool isWarning = false;
                      List<String> newMedActiveIngredients = [];

                      if (newMed.isNotEmpty) {
                        final openFda = OpenFDAService();
                        
                        // 1. Fetch drug details for allergens & duplicate ingredients
                        final medDetails = await openFda.fetchMedicationDetails(apiKey, newMed);
                        String rawAllergensAndIngredients = "";
                        
                        if (medDetails != null) {
                          newMedActiveIngredients = List<String>.from(medDetails['active_ingredient'] ?? []);
                          final inactive = (medDetails['inactive_ingredient'] as List<dynamic>?)?.join(', ') ?? '';
                          final desc = (medDetails['description'] as List<dynamic>?)?.join(', ') ?? '';
                          final warnings = (medDetails['warnings'] as List<dynamic>?)?.join(', ') ?? '';
                          final activeStr = newMedActiveIngredients.join(', ');
                          
                          rawAllergensAndIngredients = "Active ingredients: $activeStr.\nOther details (check carefully for hidden allergens): $inactive $desc\nWarnings: $warnings";
                        }
                        
                        // 2. Fetch drug-to-drug interactions
                        String rawInteractions = "";
                        if (cabinetNames.isNotEmpty) {
                           final interactions = await openFda.checkInteractions(apiKey, newMed, cabinetNames);
                           if (interactions != null) rawInteractions = interactions;
                        }
                        
                        // 3. Prompt LLM if we have cabinet meds OR if we have allergens
                        if (cabinetNames.isNotEmpty || myAllergens.isNotEmpty || newMedActiveIngredients.isNotEmpty) {
                          final llmService = LlmService();
                          final prompt = '''
You are a helpful pharmacist. Analyze the following for a patient taking a new medication "$newMed".

Patient's known allergies: ${myAllergens.isEmpty ? "None" : myAllergens.join(', ')}
New medication label data (for allergen/ingredient check): $rawAllergensAndIngredients
Cabinet medications active ingredients: ${cabinetIngredients.isEmpty ? "None" : cabinetIngredients.join(', ')}
Drug-to-Drug Interactions found on FDA label: ${rawInteractions.isEmpty ? "None found" : rawInteractions}

Perform these checks:
1. Allergen check: Does the new medication label data contain anything the patient is allergic to?
2. Duplicate active ingredients: Do the new medication's active ingredients match any of the cabinet's active ingredients?
3. Drug interactions: Summarize any severe drug-to-drug interactions listed above.

If any of these 3 checks find a conflict, risk, or issue, you MUST start your response with a 1-sentence warning verdict, then the exact string "|||", then a detailed explanation in simple language.
If ALL checks are perfectly safe and there are no duplicates, allergies, or interactions, reply EXACLY with: "No major conflicts found.|||Based on your cabinet and allergies, this medication appears safe. However, always consult a doctor."

Please use markdown formatting (like bolding and bullet points) to make your detailed explanation easy to read.
''';
                          
                          debugPrint('--- LLM PROMPT ---');
                          final pattern = RegExp('.{1,800}(?:\\s+|\\b|\$)');
                          for (final match in pattern.allMatches(prompt.replaceAll('\n', ' '))) {
                            debugPrint(match.group(0));
                          }
                          debugPrint('------------------');
                          
                          String summary = "";
                          try {
                            summary = await llmService.generateOllama(prompt);
                          } catch (e) {
                            try {
                              summary = await llmService.generateGeminiText(prompt, forceJson: false);
                            } catch (e2) {
                              summary = "Unable to complete safety check.|||Please check your internet connection or try again.";
                            }
                          }
                          
                          if (summary.contains('|||')) {
                            final parts = summary.split('|||');
                            verdict = parts[0].trim();
                            details = parts[1].trim();
                            if (!verdict.toLowerCase().contains("no major conflicts") && !verdict.toLowerCase().contains("appears safe")) {
                              isWarning = true;
                            }
                          } else {
                            isWarning = true;
                            final firstPeriod = summary.indexOf('.');
                            if (firstPeriod != -1 && firstPeriod < 100) {
                              verdict = summary.substring(0, firstPeriod + 1).trim();
                              details = summary.substring(firstPeriod + 1).trim();
                            } else {
                              verdict = "Safety check completed with notes. Please read details.";
                              details = summary.trim();
                            }
                          }
                        }
                      }

                      if (!mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicationResultsScreen(
                            medicationName: _nameController.text,
                            dosage: _dosageController.text,
                            frequency: _freqController.text,
                            verdict: verdict,
                            interactionDetails: details,
                            isWarning: isWarning,
                            activeIngredients: newMedActiveIngredients.isNotEmpty ? newMedActiveIngredients : null,
                          ),
                        ),
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    } finally {
                      if (mounted) setState(() => _isLoading = false);
                    }
                  },
                  child: _isLoading 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                      : const Text(
                          'Check Interactions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38),
            prefixIcon: Icon(icon, color: Colors.blue),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blueAccent.shade700, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}