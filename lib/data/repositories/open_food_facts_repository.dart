import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/product_data.dart';
import '../../domain/repositories/i_product_repository.dart';

final openFoodFactsRepositoryProvider = Provider((ref) => OpenFoodFactsRepository());

class OpenFoodFactsRepository implements IProductRepository {
  final Dio _dio;

  OpenFoodFactsRepository({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://world.openfoodfacts.org/',
              headers: {'User-Agent': 'AndroidTestLlm/1.0 (OFF lookup)'},
            )) {
    // Add logging in debug mode if needed
  }

  Future<ProductData> fetchByBarcode(String barcode) async {
    final digits = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return ProductData(found: false, statusVerbose: 'empty barcode');
    }

    const fields = 'code,product_name,ingredients_text,ingredients_text_en,allergens_tags,status,status_verbose';

    var data = await _fetchV2(digits, fields);
    if (!data.found && digits.length == 12) {
      data = await _fetchV2('0$digits', fields);
    }
    if (!data.found) {
      data = await _fetchV0(digits);
    }
    return data;
  }

  Future<ProductData> _fetchV2(String barcode, String fields) async {
    try {
      final response = await _dio.get('api/v2/product/$barcode.json', queryParameters: {'fields': fields});
      return _handleResponse(response);
    } catch (e) {
      return ProductData(found: false, statusVerbose: e.toString());
    }
  }

  Future<ProductData> _fetchV0(String barcode) async {
    try {
      final response = await _dio.get('api/v0/product/$barcode.json');
      return _handleResponse(response);
    } catch (e) {
      return ProductData(found: false, statusVerbose: e.toString());
    }
  }

  ProductData _handleResponse(Response response) {
    if (response.statusCode != 200 || response.data == null) {
      return ProductData(found: false, statusVerbose: 'HTTP ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    final status = data['status'];
    final statusVerbose = data['status_verbose'];

    if (status != 1 || data['product'] == null) {
      return ProductData(found: false, statusVerbose: statusVerbose?.toString());
    }

    final product = data['product'] as Map<String, dynamic>;
    String? ingredients = product['ingredients_text_en'];
    if (ingredients == null || ingredients.isEmpty) {
      ingredients = product['ingredients_text'];
    }

    return ProductData(
      found: true,
      code: product['code']?.toString(),
      name: product['product_name']?.toString(),
      ingredients: ingredients,
      statusVerbose: statusVerbose?.toString(),
    );
  }
}
