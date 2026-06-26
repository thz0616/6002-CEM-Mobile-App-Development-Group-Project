class AccountTransaction {
  final int? id;
  final String type;
  final double amount;
  final String currency;
  final String category;
  final String merchant;
  final DateTime transactionDate;
  final String note;
  final String? sourceImagePath;
  final String? rawLlmJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  AccountTransaction({
    this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.category,
    required this.merchant,
    required this.transactionDate,
    required this.note,
    this.sourceImagePath,
    this.rawLlmJson,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'currency': currency,
      'category': category,
      'merchant': merchant,
      'transaction_date': transactionDate.toIso8601String(),
      'note': note,
      'source_image_path': sourceImagePath,
      'raw_llm_json': rawLlmJson,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory AccountTransaction.fromMap(Map<String, dynamic> map) {
    return AccountTransaction(
      id: map['id'] as int?,
      type: map['type']?.toString() ?? 'expense',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'MYR',
      category: map['category']?.toString() ?? 'other',
      merchant: map['merchant']?.toString() ?? '',
      transactionDate:
          DateTime.tryParse(map['transaction_date']?.toString() ?? '') ??
          DateTime.now(),
      note: map['note']?.toString() ?? '',
      sourceImagePath: map['source_image_path']?.toString(),
      rawLlmJson: map['raw_llm_json']?.toString(),
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  AccountTransaction copyWith({
    int? id,
    String? type,
    double? amount,
    String? currency,
    String? category,
    String? merchant,
    DateTime? transactionDate,
    String? note,
    String? sourceImagePath,
    String? rawLlmJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AccountTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      merchant: merchant ?? this.merchant,
      transactionDate: transactionDate ?? this.transactionDate,
      note: note ?? this.note,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      rawLlmJson: rawLlmJson ?? this.rawLlmJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
