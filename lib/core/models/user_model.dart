/// Represents a rider user profile as returned by the backend.
class UserModel {
  final String id;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String role; // 'RIDER', 'DRIVER', etc.
  final String? email;
  final bool isActive;

  const UserModel({
    required this.id,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.avatarUrl,
    this.role = 'RIDER',
    this.email,
    this.isActive = true,
  });

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? phoneNumber ?? 'مستخدم';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      role: json['role'] as String? ?? 'RIDER',
      email: json['email'] as String?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'role': role,
      if (email != null) 'email': email,
      'isActive': isActive,
    };
  }
}
