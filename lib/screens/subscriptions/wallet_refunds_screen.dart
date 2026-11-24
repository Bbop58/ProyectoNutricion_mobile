import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/email_document_button.dart';
import 'subscription_receipts_section.dart';

class WalletRefundsScreen extends StatefulWidget {
  const WalletRefundsScreen({super.key});
  @override
  State<WalletRefundsScreen> createState() => _WalletRefundsScreenState();
}

class _RefundReasonDialog extends StatefulWidget {
  final String amount;
  const _RefundReasonDialog(this.amount);
  @override
  State<_RefundReasonDialog> createState() => _RefundReasonDialogState();
}

class _RefundReasonDialogState extends State<_RefundReasonDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Devolver todo a mi wallet'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Solicitarás ${widget.amount} USD como saldo para consultas. Si se aprueba, se cerrará el Premium de ese período. No se devuelve dinero a PayPal.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Motivo de la devolución',
              helperText: 'Mínimo 3 caracteres',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: reason,
        builder: (_, value, _) => FilledButton(
          onPressed: value.text.trim().length < 3
              ? null
              : () => Navigator.pop(context, value.text.trim()),
          child: const Text('Confirmar solicitud'),
        ),
      ),
    ],
  );
}

class _WalletRefundsScreenState extends State<WalletRefundsScreen> {
  bool _busy = false, _ready = false, _hasMore = false;
  String? _error;
  Map<String, dynamic>? _subscription, _receipt;
  final List<Map<String, dynamic>> _refunds = [];
  double? _balance;
  ApiService get _api => context.read<ApiService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    final api = _api;
    final owner = api.currentUserId;
    if (owner == null) return;
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
    });
    try {
      final rows = await Future.wait([
        api.get('/subscriptions/current', usarCache: false),
        api.get('/subscriptions/receipts?limit=100', usarCache: false),
        api.get(
          '/subscriptions/wallet-refunds?limit=20&offset=${more ? _refunds.length : 0}',
          usarCache: false,
        ),
        api.get('/wallet', usarCache: false),
      ]);
      if (!mounted || owner != api.currentUserId) return;
      final subscription = rows[0] as Map<String, dynamic>?;
      final receipts = rows[1] as List;
      final matching = receipts.where((r) => r['id'] == subscription?['id']);
      setState(() {
        _subscription = subscription;
        _receipt = matching.isEmpty
            ? null
            : Map<String, dynamic>.from(matching.first as Map);
        if (!more) _refunds.clear();
        _refunds.addAll(
          (rows[2] as List).map((r) => Map<String, dynamic>.from(r as Map)),
        );
        _hasMore = (rows[2] as List).length == 20;
        _balance = ((rows[3] as Map)['balance'] as num).toDouble();
        _ready = true;
      });
      if (mounted && owner == api.currentUserId) {
        await context.read<SubscriptionService>().fetchCurrentSubscription(
          userId: owner,
        );
      }
    } catch (e) {
      if (mounted && owner == api.currentUserId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && owner == api.currentUserId) setState(() => _busy = false);
    }
  }

  bool get _canRequest =>
      _ready &&
      _subscription?['plan_name'] == 'CLIENTE_PREMIUM' &&
      _subscription?['status'] == 'ACTIVE' &&
      _receipt != null &&
      !(_receipt?['paypal_capture_id'] as String? ?? '')
          .toUpperCase()
          .startsWith('DEMO-') &&
      !_refunds.any((r) => r['subscription_id'] == _subscription?['id']);

  Future<void> _request() async {
    if (_busy || !_canRequest) return;
    final owner = _api.currentUserId;
    final subscriptionId = _subscription!['id'];
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _RefundReasonDialog(_money(_receipt!['amount'])),
    );
    if (text == null || !mounted || owner != _api.currentUserId) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.post(
        '/subscriptions/wallet-refunds',
        body: {'subscription_id': subscriptionId, 'reason': text},
      );
      if (!mounted || owner != _api.currentUserId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitud enviada. Premium continúa activo mientras se revisa.',
          ),
        ),
      );
    } catch (e) {
      if (mounted && owner == _api.currentUserId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && owner == _api.currentUserId) setState(() => _busy = false);
    }
    if (mounted && owner == _api.currentUserId && _error == null) await _load();
  }

  Future<void> _download(String id) async {
    if (_busy) return;
    final owner = _api.currentUserId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _api.getBytes(
        '/subscriptions/wallet-refunds/$id/pdf',
      );
      if (!mounted || owner != _api.currentUserId) return;
      await saveReceiptPdf(bytes, 'Devolucion_wallet_$id.pdf');
    } catch (e) {
      if (mounted && owner == _api.currentUserId) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && owner == _api.currentUserId) setState(() => _busy = false);
    }
  }

  String _money(dynamic amount) =>
      ((amount is num ? amount : num.parse(amount.toString()))).toStringAsFixed(
        2,
      );
  String _status(dynamic value) => switch (value) {
    'APPROVED' => 'Acreditado a wallet',
    'REJECTED' => 'Rechazado',
    _ => 'Pendiente de revisión',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Devoluciones a wallet')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Devolución total de Premium IA',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Requiere internet. El saldo aprobado sirve para consultas y no se retira a PayPal.',
          ),
          if (_balance != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Saldo wallet: ${_money(_balance)} USD'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          OutlinedButton(
            onPressed: _busy ? null : _load,
            child: const Text('Actualizar estado y saldo'),
          ),
          if (_canRequest)
            FilledButton(
              onPressed: _busy ? null : _request,
              child: Text(
                'Solicitar devolución de ${_money(_receipt!['amount'])} USD',
              ),
            ),
          if (_ready && !_canRequest && _refunds.isEmpty)
            const Text(
              'No tienes un pago Premium vigente disponible para devolver. Los planes sin cobro y los recibos DEMO no son reembolsables.',
            ),
          for (final r in _refunds)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_money(r['amount'])} ${r['currency']} · ${_status(r['status'])}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (r['is_sandbox'] == true)
                      const Text('Sandbox · operación de prueba'),
                    Text('Motivo: ${r['reason']}'),
                    if (r['decision_reason'] != null)
                      Text('Respuesta: ${r['decision_reason']}'),
                    if (r['status'] == 'APPROVED')
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _download(r['id'] as String),
                            icon: const Icon(Icons.download),
                            label: const Text('Descargar comprobante PDF'),
                          ),
                          EmailDocumentButton(
                            pdfPath:
                                '/subscriptions/wallet-refunds/${r['id']}/pdf',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (_hasMore)
            TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: const Text('Ver más solicitudes'),
            ),
        ],
      ),
    ),
  );
}
