class Medication {
  final int? id;
  final String name;
  final String dosage;
  final String frequency;
  final String dateAdded;
  final List<String>? activeIngredients;

  Medication({
    this.id,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.dateAdded,
    this.activeIngredients,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'],
      name: json['name'],
      dosage: json['dosage'],
      frequency: json['frequency'],
      dateAdded: json['date_added'],
      activeIngredients: json['active_ingredients'] != null 
          ? List<String>.from(json['active_ingredients'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'date_added': dateAdded,
      if (activeIngredients != null) 'active_ingredients': activeIngredients,
    };
  }
}