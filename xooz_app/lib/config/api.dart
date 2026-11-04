class ApiConfig {
  // Phone testing: use localhost + [adb reverse tcp:8000 tcp:8000]
  // 127.0.0.1 is Android's alias for localhost; using it avoids confusion with "10.0.2.2" needed on emulators
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';

  // Audio
  static const String uploadAudio = '$baseUrl/audio';

  // Transcripts
  static const String transcripts = '$baseUrl/transcripts';
  static String transcriptDetail(String id) => '$baseUrl/transcripts/$id';

  // Digests (recaps)
  static String getDigest(String userId) => '$baseUrl/digest/$userId';
  static String getDigests(String userId) => '$baseUrl/digests/$userId';

  // Tasks
  static const String tasks = '$baseUrl/tasks';
  static String taskDetail(String id) => '$baseUrl/tasks/$id';

  // Chat ("Ask Anything")
  static const String chat = '$baseUrl/chat';
  static const String chatHistory = '$baseUrl/chat/history';

  // Search
  static const String search = '$baseUrl/search';
  static const String categoryCounts = '$baseUrl/categories/counts';

  // Activity feed
  static String activity(String userId) => '$baseUrl/activity/$userId';

  // Profile & usage
  static const String me = '$baseUrl/me';
  static const String usage = '$baseUrl/usage';

  // Devices (Xooz Watch)
  static String devices(String userId) => '$baseUrl/devices?user_id=$userId';
  static const String devicePair = '$baseUrl/devices/pair';

  // Temporary hardcoded user ID for testing
  // Replace with real auth later
  static const String testUserId = 'test_user_1';
}
