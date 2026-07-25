/// OpenWeatherMap yapılandırması (ücretsiz kota).
abstract final class WeatherApiConfig {
  static const apiKey = '6ef5a34093512e8ce92ff4e845063e80';
  static const weatherUrl = 'https://api.openweathermap.org/data/2.5/weather';

  static bool get isConfigured => apiKey.trim().isNotEmpty;
}
