class ApiConfig {
  // Change this to your machine's local IP when testing on a real device
  // Keep localhost only for emulator testing
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

  static const String uploadAudio = '$baseUrl/audio';
  static String getDigest(String userId) => '$baseUrl/digest/$userId';

  // Temporary hardcoded user ID for testing
  // Replace with real auth later
  static const String testUserId = 'test_user_1';
}