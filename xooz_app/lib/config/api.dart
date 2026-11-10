class ApiConfig {
  // Change this to your machine's local IP when testing on a real device
  // Keep localhost only for emulator testing
  static const String baseUrl = 'http://192.168.1.6:8001/api/v1';

  static const String uploadAudio = '$baseUrl/audio';
  static const String recaps = '$baseUrl/recap';
  static const String transcripts = '$baseUrl/transcripts';
  static const String tasks = '$baseUrl/tasks';
  static const String chat = '$baseUrl/chat';
  static const String search = '$baseUrl/search';
  static const String categoryCounts = '$baseUrl/categories/counts';
  static const String me = '$baseUrl/me';
  static const String usage = '$baseUrl/usage';

  static String getDigest(String userId) => '$baseUrl/digest/$userId';
  static String getDigests(String userId) => '$baseUrl/digests/$userId';
  static String getRecap(String userId) => '$recaps/$userId';
  static String transcriptDetail(String transcriptId) =>
      '$transcripts/$transcriptId';
  static String taskDetail(String taskId) => '$tasks/$taskId';
  static String activity(String userId) => '$baseUrl/activity/$userId';

  // Temporary hardcoded user ID for testing
  // Replace with real auth later
  static const String testUserId = 'test_user_1';
}
