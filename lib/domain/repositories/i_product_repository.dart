import '../models/product_data.dart';

abstract class IProductRepository {
  Future<ProductData> fetchByBarcode(String barcode);
}
