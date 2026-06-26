import 'package:dio/dio.dart';

class OpenFDAService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// Checks for drug interactions between a new medication and a list of existing medications.
  /// Returns a combined string of interaction warnings if found, otherwise returns null.
  Future<String?> checkInteractions(String apiKey, String newMed, List<String> cabinetMeds) async {
    if (apiKey.isEmpty) {
      throw Exception('OpenFDA API key is required. Please set it in Settings.');
    }

    List<String> foundInteractions = [];

    for (final cabinetMed in cabinetMeds) {
      // 1. Check if newMed label mentions cabinetMed
      try {
        final encodedNewMed = Uri.encodeComponent(newMed.toLowerCase());
        final encodedCabMed = Uri.encodeComponent(cabinetMed.toLowerCase());
        
        final search1 = '(openfda.generic_name:"$encodedNewMed"+openfda.brand_name:"$encodedNewMed")+AND+drug_interactions:"$encodedCabMed"';
        final url1 = 'https://api.fda.gov/drug/label.json?api_key=$apiKey&search=$search1&limit=1';
        
        final response1 = await _dio.get(url1);

        if (response1.statusCode == 200) {
          final results = response1.data['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final interactions = results[0]['drug_interactions'] as List<dynamic>?;
            if (interactions != null && interactions.isNotEmpty) {
              foundInteractions.add('Interaction from ${newMed.toUpperCase()} label:\n${interactions[0]}');
            }
          }
        }
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
      
      // 2. Check if cabinetMed label mentions newMed
      try {
        final encodedNewMed = Uri.encodeComponent(newMed.toLowerCase());
        final encodedCabMed = Uri.encodeComponent(cabinetMed.toLowerCase());
        
        final search2 = '(openfda.generic_name:"$encodedCabMed"+openfda.brand_name:"$encodedCabMed")+AND+drug_interactions:"$encodedNewMed"';
        final url2 = 'https://api.fda.gov/drug/label.json?api_key=$apiKey&search=$search2&limit=1';
        
        final response2 = await _dio.get(url2);

        if (response2.statusCode == 200) {
          final results = response2.data['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final interactions = results[0]['drug_interactions'] as List<dynamic>?;
            if (interactions != null && interactions.isNotEmpty) {
              foundInteractions.add('Interaction from ${cabinetMed.toUpperCase()} label:\n${interactions[0]}');
            }
          }
        }
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
    }

    if (foundInteractions.isEmpty) return null;
    return foundInteractions.join('\n\n---\n\n');
  }

  /// Fetches detailed label information for a specific medication.
  /// Returns a map with 'active_ingredient', 'inactive_ingredient', and 'warnings'.
  Future<Map<String, dynamic>?> fetchMedicationDetails(String apiKey, String medName) async {
    if (apiKey.isEmpty) return null;

    try {
      final encodedMed = Uri.encodeComponent(medName.toLowerCase());
      final search = '(openfda.generic_name:*$encodedMed*+openfda.brand_name:*$encodedMed*)';
      final url = 'https://api.fda.gov/drug/label.json?api_key=$apiKey&search=$search&limit=25';
      
      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final results = response.data['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          var result = results[0];
          for (var r in results) {
            final inactive = r['inactive_ingredient'] as List<dynamic>?;
            if (inactive != null && inactive.isNotEmpty) {
              result = r;
              break;
            }
          }
          
          
          List<String> getFieldLines(String key) {
            final field = result[key] as List<dynamic>?;
            if (field != null && field.isNotEmpty) {
              return field.map((e) => e.toString()).toList();
            }
            return [];
          }

          final openfda = result['openfda'] as Map<String, dynamic>?;
          
          List<String> getOpenFdaLines(String key) {
            if (openfda == null) return [];
            final field = openfda[key] as List<dynamic>?;
            if (field != null && field.isNotEmpty) {
              return field.map((e) => e.toString()).toList();
            }
            return [];
          }

          List<String> activeIngredients = getFieldLines('active_ingredient');
          if (activeIngredients.isEmpty) activeIngredients.addAll(getOpenFdaLines('substance_name'));
          if (activeIngredients.isEmpty) activeIngredients.addAll(getOpenFdaLines('generic_name'));

          return {
            'active_ingredient': activeIngredients,
            'inactive_ingredient': getFieldLines('inactive_ingredient'),
            'description': getFieldLines('description'),
            'warnings': getFieldLines('warnings'),
          };
        }
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    
    return null;
  }
}