import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/config/theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/theme_service.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('LoginScreen renders email, password, and login button', (
    WidgetTester tester,
  ) async {
    final storageService = StorageService();
    final apiService = ApiService(storageService);
    final authService = AuthService(apiService, storageService);
    final themeService = ThemeService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          Provider<ApiService>.value(value: apiService),
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const LoginScreen(),
        ),
      ),
    );

    // Verify brand, input fields and login button
    expect(find.text('NutriSalud'), findsOneWidget);
    expect(find.text('Correo Electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets(
    'LoginScreen shows validation errors when fields are empty on submit',
    (WidgetTester tester) async {
      final storageService = StorageService();
      final apiService = ApiService(storageService);
      final authService = AuthService(apiService, storageService);
      final themeService = ThemeService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storageService),
            Provider<ApiService>.value(value: apiService),
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<ThemeService>.value(value: themeService),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const LoginScreen(),
          ),
        ),
      );

      // Tap submit without entering data
      await tester.ensureVisible(find.text('Iniciar sesión'));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      // Verify empty field validation indicators
      expect(find.text('Por favor, rellene este campo'), findsNWidgets(2));
      expect(
        find.text('Por favor, rellene todos los campos para iniciar sesión'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'LoginScreen accepts existing passwords without registration complexity rules',
    (WidgetTester tester) async {
      final storageService = StorageService();
      final apiService = ApiService(storageService);
      final authService = AuthService(apiService, storageService);
      final themeService = ThemeService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storageService),
            Provider<ApiService>.value(value: apiService),
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<ThemeService>.value(value: themeService),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const LoginScreen(),
          ),
        ),
      );

      final passwordField = tester.widget<TextFormField>(
        find.byType(TextFormField).last,
      );
      expect(passwordField.validator!(''), isNotNull);
      expect(
        passwordField.validator!('0JyD3nNqfgjVpr0zk4XiO9bbsLc4D2lC'),
        isNull,
      );
      expect(passwordField.validator!('pass'), isNull);
    },
  );
}
