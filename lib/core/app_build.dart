class AppBuild {
  AppBuild._();

  static const String number = String.fromEnvironment(
    'APP_BUILD_NUMBER', defaultValue: 'development',
  );
  static const String revision = String.fromEnvironment(
    'APP_BUILD_REVISION', defaultValue: 'Local build',
  );
  static const String label = 'Version 1.0.0 ($number)';
}
