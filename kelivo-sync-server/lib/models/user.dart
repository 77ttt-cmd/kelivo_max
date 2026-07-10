class User {
  final int id;
  final String username;
  final String passwordHash;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.createdAt,
  });
}
