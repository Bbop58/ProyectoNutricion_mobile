class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'https://backend-api-production-d40295b0.up.railway.app/api/v1',
  );
}
