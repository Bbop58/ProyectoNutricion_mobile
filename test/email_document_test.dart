import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/email_document_button.dart';

void main() {
  testWidgets(
    'Prefills email and sends edited address with selected PDF/Excel and query',
    (tester) async {
      Map<String, dynamic>? sent;
      final query = {
        'entity': 'patients',
        'branch_ids': ['branch-a'],
        'start_date': '2026-10-01',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailDocumentDialog(
              initialEmail: 'account@example.com',
              pdfPath: '/reports/export/pdf',
              excelPath: '/reports/export/excel',
              payload: query,
              send: (body) async {
                sent = body;
              },
            ),
          ),
        ),
      );
      expect(find.text('account@example.com'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'edited@gmail.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
      await tester.pumpAndSettle();
      expect(sent?['email'], 'edited@gmail.com');
      expect(sent?['paths'], ['/reports/export/pdf', '/reports/export/excel']);
      expect(sent?['report_request'], query);
      expect(find.text('Enviado a edited@gmail.com.'), findsOneWidget);
    },
  );
  testWidgets('Rejects invalid email and shows provider failure', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmailDocumentDialog(
            initialEmail: 'invalid',
            pdfPath: '/appointments/a/pdf',
            send: (body) async {
              calls++;
              throw Exception('Unavailable');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'edited@gmail.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('No se pudo enviar.'), findsOneWidget);
    expect(find.textContaining('Enviado a'), findsNothing);
  });
}
