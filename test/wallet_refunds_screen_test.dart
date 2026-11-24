import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/subscription_service.dart';
import 'package:mobile/screens/subscriptions/wallet_refunds_screen.dart';

class RefundSubscriptions extends ChangeNotifier
    implements SubscriptionService {
  @override
  Future<void> fetchCurrentSubscription({String? userId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'confirms full amount, posts only identity/reason and refreshes approved wallet',
    (tester) async {
      var requested = false, approved = false;
      final posted = <Map<String, dynamic>>[];
      final api = ApiService(
        StorageService(),
        client: MockClient((r) async {
          dynamic data;
          if (r.url.path.endsWith('/current')) {
            data = approved
                ? null
                : {
                    'id': 'sub',
                    'plan_name': 'CLIENTE_PREMIUM',
                    'status': 'ACTIVE',
                  };
          } else if (r.url.path.endsWith('/receipts')) {
            data = [
              {'id': 'sub', 'amount': 5, 'paypal_capture_id': 'CAPTURE'},
            ];
          } else if (r.url.path.endsWith('/wallet')) {
            data = {'balance': approved ? 5 : 0};
          } else if (r.url.path.endsWith('/wallet-refunds')) {
            if (r.method == 'POST') {
              requested = true;
              posted.add(jsonDecode(r.body) as Map<String, dynamic>);
              data = {'id': 'refund'};
            } else {
              data = requested
                  ? [
                      {
                        'id': 'refund',
                        'subscription_id': 'sub',
                        'amount': '5.00',
                        'currency': 'USD',
                        'status': approved ? 'APPROVED' : 'PENDING',
                        'reason': 'Devolver a mi wallet',
                        'decision_reason': approved ? 'Aprobado' : null,
                      },
                    ]
                  : [];
            }
          } else {
            throw StateError('Unexpected endpoint ${r.url}');
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..currentUserId = 'patient';
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider<SubscriptionService>.value(
              value: RefundSubscriptions(),
            ),
          ],
          child: const MaterialApp(home: WalletRefundsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solicitar devolución de 5.00 USD'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No se devuelve dinero a PayPal.'),
        findsWidgets,
      );
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar solicitud'),
      );
      expect(confirm.onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Devolver a mi wallet');
      await tester.pump();
      await tester.tap(find.text('Confirmar solicitud'));
      await tester.pumpAndSettle();
      expect(posted, [
        {'subscription_id': 'sub', 'reason': 'Devolver a mi wallet'},
      ]);
      expect(find.textContaining('Pendiente de revisión'), findsOneWidget);
      expect(find.text('Solicitar devolución de 5.00 USD'), findsNothing);
      approved = true;
      await tester.tap(find.text('Actualizar estado y saldo'));
      await tester.pumpAndSettle();
      expect(find.text('Saldo wallet: 5.00 USD'), findsOneWidget);
      expect(find.textContaining('Acreditado a wallet'), findsOneWidget);
      expect(find.text('Descargar comprobante PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('network failure does not allow an offline refund', (
    tester,
  ) async {
    var writes = 0;
    final api = ApiService(
      StorageService(),
      client: MockClient((r) async {
        if (r.method == 'POST') writes++;
          throw http.ClientException('Sin red');
      }),
    )..currentUserId = 'patient';
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<SubscriptionService>.value(
            value: RefundSubscriptions(),
          ),
        ],
        child: const MaterialApp(home: WalletRefundsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Error de conexión con el servidor.'), findsOneWidget);
    expect(find.textContaining('Solicitar devolución de'), findsNothing);
    expect(writes, 0);
  });
}
