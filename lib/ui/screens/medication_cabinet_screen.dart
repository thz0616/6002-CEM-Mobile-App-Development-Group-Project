import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'medication_validation_screen.dart';
import '../../data/repositories/medication_storage.dart';
import '../../domain/models/medication.dart';
import '../../data/services/llm_service.dart';

class MedicationCabinetScreen extends StatefulWidget {
  const MedicationCabinetScreen({super.key});

  @override
  State<MedicationCabinetScreen> createState() => _MedicationCabinetScreenState();
}

class _MedicationCabinetScreenState extends State<MedicationCabinetScreen> {
  late Future<List<Medication>> _medicationsFuture;
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  void _loadMedications() {
    setState(() {
      _medicationsFuture = MedicationStorage().getMedications();
    });
  }

  Future<void> _processImage(ImageSource source) async {
    Navigator.pop(context); // Close bottom sheet
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() => _isProcessingImage = true);

    try {
      final llmService = LlmService();
      final extractedData = await llmService.extractMedicationFromImageOllama(pickedFile.path);

      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MedicationValidationScreen(
            initialName: extractedData['name'] ?? '',
            initialDosage: extractedData['dosage'] ?? '',
            initialFrequency: extractedData['frequency'] ?? '',
          ),
        ),
      ).then((_) => _loadMedications());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => _processImage(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => _processImage(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Enter Manually'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MedicationValidationScreen(
                        initialName: '',
                        initialDosage: '',
                        initialFrequency: '',
                      ),
                    ),
                  ).then((_) => _loadMedications());
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medication Cabinet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent.shade400,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: FutureBuilder<List<Medication>>(
        future: _medicationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.shade400,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.medication, size: 56, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Medications Tracked',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48.0),
                    child: Text(
                      'Tap "Add New" to photograph a medication label.\nThe assistant will extract the details automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500, height: 1.5),
                    ),
                  ),
                ],
              ),
            );
          }

          final meds = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: meds.length,
            itemBuilder: (context, index) {
              final med = meds[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.medication, color: Colors.blue),
                  ),
                  title: Text(med.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text('${med.dosage} • ${med.frequency}'),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () async {
                      meds.removeAt(index);
                      await MedicationStorage().saveMedications(meds);
                      _loadMedications();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        onPressed: _isProcessingImage ? null : _showAddOptions,
        icon: _isProcessingImage 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
        label: Text(_isProcessingImage ? 'Processing...' : 'Add New', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
