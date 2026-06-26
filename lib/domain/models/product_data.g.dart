// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductData _$ProductDataFromJson(Map<String, dynamic> json) => ProductData(
  found: json['found'] as bool,
  code: json['code'] as String?,
  name: json['name'] as String?,
  ingredients: json['ingredients'] as String?,
  statusVerbose: json['statusVerbose'] as String?,
);

Map<String, dynamic> _$ProductDataToJson(ProductData instance) =>
    <String, dynamic>{
      'found': instance.found,
      'code': instance.code,
      'name': instance.name,
      'ingredients': instance.ingredients,
      'statusVerbose': instance.statusVerbose,
    };
