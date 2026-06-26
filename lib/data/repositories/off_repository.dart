import 'package:dio/dio.dart';

class ProductData {
  final bool found;
  final String? code;
  final String? name;
  final String? ingredients;
  final String? statusVerbose;

  ProductData({
    required this.found,
    this.code,
    this.name,
    this.ingredients,
    this.statusVerbose,
  });
}

class OffRepository {
  static final OffRepository _instance = OffRepository._internal();
  static OffRepository get instance => _instance;

  late Dio _dio;

  OffRepository._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://world.openfoodfacts.org/',
      headers: {
        'User-Agent': 'AndroidTestLlmFlutter/1.0 (OFF lookup)',
      },
    ));
  }

  Future<ProductData> fetchByBarcode(String? barcode) async {
    String digits = barcode?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (digits.isEmpty) {
      return ProductData(found: false, statusVerbose: 'empty barcode');
    }

    String fields = 'code,product_name,ingredients_text,ingredients_text_en,allergens_tags,status,status_verbose';
    
    ProductData d = await _fetchV2(digits, fields);
    if (!d.found && digits.length == 12) {
      // Try EAN-13 from UPC-A
      d = await _fetchV2('0$digits', fields);
    }
    
    if (!d.found) {
      d = await _fetchV0(digits);
    }
    
    return d;
  }

  Future<ProductData> _fetchV2(String barcode, String fields) async {
    try {
      final response = await _dio.get('api/v2/product/$barcode.json', queryParameters: {
        'fields': fields,
      });
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
    
    final body = response.data;
    if (body['status'] != 1 || body['product'] == null) {
      return ProductData(found: false, statusVerbose: body['status_verbose']);
    }

    final product = body['product'];
    String? ingredients = product['ingredients_text_en'];
    if (ingredients == null || ingredients.isEmpty) {
      ingredients = product['ingredients_text'];
    }

    return ProductData(
      found: true,
      code: product['code'],
      name: product['product_name'],
      ingredients: ingredients,
      statusVerbose: body['status_verbose'],
    );
  }
}
