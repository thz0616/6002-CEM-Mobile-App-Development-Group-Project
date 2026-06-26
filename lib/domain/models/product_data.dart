import 'package:json_annotation/json_annotation.dart';

part 'product_data.g.dart';

@JsonSerializable()
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

  factory ProductData.fromJson(Map<String, dynamic> json) => _$ProductDataFromJson(json);
  Map<String, dynamic> toJson() => _$ProductDataToJson(this);
}
