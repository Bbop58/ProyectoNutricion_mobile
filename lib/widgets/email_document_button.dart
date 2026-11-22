import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class EmailDocumentButton extends StatelessWidget {
  final String pdfPath;
  final String? excelPath;
  final Map<String, dynamic>? payload;
  final bool enabled;
  const EmailDocumentButton({
    super.key,
    required this.pdfPath,
    this.excelPath,
    this.payload,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.mail_outline),
    label: const Text('Enviar al correo'),
    onPressed: !enabled
        ? null
        : () {
            final email = context.read<AuthService>().currentUser?.email ?? '';
            final api = context.read<ApiService>();
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => EmailDocumentDialog(
                initialEmail: email,
                pdfPath: pdfPath,
                excelPath: excelPath,
                payload: payload,
                send: (body) => api.post('/documents/email', body: body),
              ),
            );
          },
  );
}

class EmailDocumentDialog extends StatefulWidget {
  final String initialEmail, pdfPath;
  final String? excelPath;
  final Map<String, dynamic>? payload;
  final Future<dynamic> Function(Map<String, dynamic>) send;
  const EmailDocumentDialog({
    super.key,
    required this.initialEmail,
    required this.pdfPath,
    this.excelPath,
    this.payload,
    required this.send,
  });
  @override
  State<EmailDocumentDialog> createState() => _EmailDocumentDialogState();
}

class _EmailDocumentDialogState extends State<EmailDocumentDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false, _pdf = true, _excel = true;
  String? _error, _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.send({
        'email': _email.text.trim(),
        'paths': [
          if (_pdf) widget.pdfPath,
          if (widget.excelPath != null && _excel) widget.excelPath!,
        ],
        if (widget.payload != null) 'report_request': widget.payload,
      });
      if (mounted) {
        setState(() => _message = 'Enviado a ${_email.text.trim()}.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo enviar. Revisa el correo y tu conexión e intenta nuevamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Enviar al correo'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo destinatario',
                ),
                validator: (v) =>
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Escribe un correo válido.',
              ),
              if (widget.excelPath != null) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('PDF'),
                  value: _pdf,
                  onChanged: _busy ? null : (v) => setState(() => _pdf = v!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Excel'),
                  value: _excel,
                  onChanged: _busy ? null : (v) => setState(() => _excel = v!),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_message != null) Text(_message!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _busy || (!_pdf && !_excel) ? null : _send,
          child: Text(_busy ? 'Enviando…' : 'Enviar'),
        ),
      ],
    ),
  );
}
