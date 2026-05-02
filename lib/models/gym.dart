class Gym {
  final String id;
  final String name;
  final String? address;
  final String? phoneNumber;
  final String? emailAddress;
  final String? cityName;
  final bool isActive;
  final DateTime createdAt;

  Gym({
    required this.id,
    required this.name,
    this.address,
    this.phoneNumber,
    this.emailAddress,
    this.cityName,
    required this.isActive,
    required this.createdAt,
  });

  // Getter aliases for compatibility
  String? get phone => phoneNumber;
  String? get email => emailAddress;
  String? get city => cityName;

  factory Gym.fromJson(Map<String, dynamic> json) {
    return Gym(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Gym',
      address: json['address'] as String?,
      phoneNumber: json['phone_number'] as String?,
      emailAddress: json['email'] as String?,
      cityName: json['city'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone_number': phoneNumber,
      'email': emailAddress,
      'city': cityName,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
