import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/screens/care/care_screen.dart';

class CareTestAuth extends ChangeNotifier implements AuthService {
  @override
  User get currentUser => User(
    id: 'patient',
    email: 'patient@example.com',
    fullName: 'Paciente',
    roleId: 'CLIENTE',
    tenantId: 'a',
    isActive: true,
    isVerified: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Patient sees own progress and sends a message to linked nutritionist',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final sent = <Map<String, dynamic>>[];
      final messages = <Map<String, dynamic>>[];
      final api = ApiService(
        StorageService(),
        client: MockClient((request) async {
          final path = request.url.path;
          dynamic data;
          if (path.endsWith('/care/contacts')) {
            data = [
              {'id': 'doctor', 'full_name': 'Dra. Ana'},
            ];
          } else if (path.endsWith('/patient/assessments') &&
              request.method == 'POST') {
            data = {
              'adherence_percent': 50,
              'registered': 2,
              'expected': 4,
              'missing_days': ['2026-11-01'],
              'configuration': {'version': 1},
              'start_date': '2026-11-01',
              'end_date': '2026-11-02',
              'explanation': 'Registro de comidas, no cumplimiento clínico.',
              'formula': 'Suma diaria registrada / meta.',
              'inactivity': {'alert': false},
              'measurements': [],
              'habits': [],
              'notes': ['Hay datos faltantes.'],
              'days': [],
            };
          } else if (path.endsWith('/patient/assessments')) {
            data = [];
          } else if (path.endsWith('/conversations/doctor')) {
            if (request.method == 'POST') {
              final body = Map<String, dynamic>.from(
                jsonDecode(request.body) as Map,
              );
              sent.add(body);
              messages.add({
                'id': 'msg',
                'sender_id': 'patient',
                'content': body['content'],
                'created_at': '2026-11-22T15:00:00Z',
              });
              data = messages.last;
            } else {
              data = {'items': messages, 'has_more': false};
            }
          } else {
            return http.Response('Unknown request $path', 404);
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final auth = CareTestAuth();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: const MaterialApp(home: CareScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver seguimiento'));
      await tester.pumpAndSettle();
      expect(find.text('50% de registro'), findsOneWidget);
      expect(
        find.text('Registro de comidas, no cumplimiento clínico.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mensajes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dra. Ana').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Consulta de porciones',
      );
      await tester.ensureVisible(find.text('Enviar mensaje'));
      await tester.tap(find.text('Enviar mensaje'));
      await tester.pumpAndSettle();
      expect(sent.single['content'], 'Consulta de porciones');
      expect(find.text('Consulta de porciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
