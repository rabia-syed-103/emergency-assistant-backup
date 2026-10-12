// lib/config.dart
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    //defaultValue: 'https://emergency-assistant-backup-production.up.railway.app',
     
    defaultValue: 'http://172.16.21.241:8000'
  );
}