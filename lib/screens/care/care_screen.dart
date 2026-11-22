import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class CareScreen extends StatefulWidget {
  const CareScreen({super.key});
  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends State<CareScreen> {
  bool _busy = false, _hasMore = false;
  String? _error, _peer, _patient;
  int _offset = 0;
  List<dynamic> _contacts = [], _patients = [], _messages = [], _history = [];
  Map<String, dynamic>? _report;
  final _weight = TextEditingController(),
      _height = TextEditingController(),
      _text = TextEditingController();
  final _today = DateTime.now();
  late DateTimeRange _range = DateTimeRange(
    start: DateTime(_today.year, _today.month, 1),
    end: _today,
  );
  late DateTime _measurementDate = _today;
  ApiService get api => context.read<ApiService>();
  String get _owner => context.read<AuthService>().currentUser!.id;
  bool get _isPatient =>
      context.read<AuthService>().currentUser?.roleId == 'CLIENTE';
  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _stamp(dynamic d) =>
      d.toString().replaceAll('T', ' ').split('.').first.replaceAll('Z', '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar la operación. $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final contacts = await api.get('/care/contacts', usarCache: false) as List;
    final patients = _isPatient
        ? <dynamic>[]
        : await api.get('/users/patients', usarCache: false) as List;
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _patients = patients;
        _patient = _isPatient
            ? _owner
            : patients.isEmpty
            ? null
            : patients.first['id'] as String;
      });
    }
  });
  Future<void> _assess() => _run(() async {
    if (_patient == null) return;
    final result = await api.post(
      '/care/patients/$_patient/assessments',
      body: {'start_date': _date(_range.start), 'end_date': _date(_range.end)},
    );
    final history = await api.get(
      '/care/patients/$_patient/assessments',
      usarCache: false,
    ) as List;
    if (mounted) {
      setState(() {
        _report = Map<String, dynamic>.from(result as Map);
        _history = history;
      });
    }
  });
  Future<void> _saveMeasurement() => _run(() async {
    final weight = double.tryParse(_weight.text.replaceAll(',', '.'));
    final height = double.tryParse(_height.text.replaceAll(',', '.'));
    if (weight == null ||
        weight <= 0 ||
        weight > 500 ||
        height == null ||
        height < 30 ||
        height > 260) {
      throw Exception('Revisa el peso (kg) y la talla (cm).');
    }
    if (_patient == null) return;
    final measured = _date(_measurementDate) == _date(DateTime.now())
        ? DateTime.now().toUtc().toIso8601String()
        : '${_date(_measurementDate)}T12:00:00-04:00';
    await api.post(
      '/care/patients/$_patient/measurements',
      body: {'weight_kg': weight, 'height_cm': height, 'measured_at': measured},
    );
    if (mounted) {
      setState(() => _report = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Medición guardada. Consulta el seguimiento para verla.',
          ),
        ),
      );
    }
  });
  Future<void> _readThread() async {
    if (_peer == null) return;
    final result = await api.get(
      '/care/conversations/$_peer?offset=$_offset',
      usarCache: false,
    ) as Map;
    if (mounted) {
      setState(() {
        _messages = result['items'] as List;
        _hasMore = result['has_more'] == true;
      });
    }
  }

  Future<void> _thread({bool older = false}) => _run(() async {
    _offset = older ? _offset + 50 : 0;
    await _readThread();
  });
  Future<void> _send() => _run(() async {
    if (_peer == null || _text.text.trim().isEmpty) return;
    await api.post(
      '/care/conversations/$_peer',
      body: {'content': _text.text.trim()},
    );
    _text.clear();
    _offset = 0;
    await _readThread();
  });
  Future<void> _pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (result != null && mounted) setState(() => _range = result);
  }

  Future<void> _pickMeasurementDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _measurementDate,
    );
    if (result != null && mounted) setState(() => _measurementDate = result);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento y mensajes'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Seguimiento'),
            Tab(text: 'Mensajes'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: TabBarView(children: [_progress(), _conversation()])),
        ],
      ),
    ),
  );

  Widget _progress() {
    final r = _report;
    final measurements = r?['measurements'] as List? ?? [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!_isPatient)
          DropdownButtonFormField<String>(
            initialValue: _patient,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paciente'),
            items: [
              for (final p in _patients)
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(p['full_name']),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _patient = value;
                    _report = null;
                    _history = [];
                  }),
          ),
        TextButton.icon(
          onPressed: _busy ? null : _pickRange,
          icon: const Icon(Icons.date_range),
          label: Text('${_date(_range.start)} a ${_date(_range.end)}'),
        ),
        FilledButton(
          onPressed: _busy || _patient == null ? null : _assess,
          child: const Text('Ver seguimiento'),
        ),
        ExpansionTile(
          title: const Text('Registrar una medición'),
          children: [
            TextField(
              controller: _weight,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Peso (kg)'),
            ),
            TextField(
              controller: _height,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Talla (cm)'),
            ),
            TextButton(
              onPressed: _busy ? null : _pickMeasurementDate,
              child: Text('Fecha: ${_date(_measurementDate)}'),
            ),
            FilledButton(
              onPressed: _busy || _patient == null ? null : _saveMeasurement,
              child: const Text('Guardar medición'),
            ),
          ],
        ),
        if (r != null) ...[
          const SizedBox(height: 20),
          Text(
            r['adherence_percent'] == null
                ? 'Sin días aplicables en el período'
                : '${r['adherence_percent']}% de registro',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          LinearProgressIndicator(
            value: ((r['adherence_percent'] as num?)?.toDouble() ?? 0) / 100,
          ),
          const SizedBox(height: 12),
          Text(
            '${r['registered']} comidas registradas · ${r['expected']} esperadas. ${(r['missing_days'] as List).length} días sin registros.',
          ),
          Text(
            'Período: ${r['start_date']} a ${r['end_date']} · Configuración v${r['configuration']['version']}.',
          ),
          const SizedBox(height: 12),
          Text(r['explanation']),
          Text(r['formula']),
          if (r['inactivity']['alert'] == true)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Seguimiento pendiente: ${r['inactivity']['days']} días sin registros. Umbral: ${r['inactivity']['threshold']} días.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Evolución del peso',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (measurements.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Semantics(
                label: 'Evolución del peso en orden de fecha. Valores listados debajo.',
                child: SizedBox(
                  height: 130,
                  child: CustomPaint(
                    painter: _WeightPainter(
                      measurements
                          .map((m) => (m['weight_kg'] as num).toDouble())
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          if (measurements.isEmpty)
            const Text('No hay mediciones históricas en este período.'),
          for (final m in measurements)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${m['weight_kg']} kg · ${m['height_cm']} cm · IMC ${m['bmi']}',
              ),
              subtitle: Text('Fecha: ${_stamp(m['measured_at'])} UTC'),
            ),
          for (final h in r['habits'] as List? ?? [])
            Text(
              '${h['label']}: ${h['value']} ${h['unit']} · Meta ${h['target']} · ${h['fulfilled'] == true ? 'Meta alcanzada' : 'Por revisar'}',
            ),
          for (final note in r['notes'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(note.toString()),
            ),
          ExpansionTile(
            title: const Text('Comidas por día y datos faltantes'),
            children: [
              for (final d in r['days'])
                ListTile(
                  title: Text(d['date']),
                  subtitle: Text(
                    '${d['registered']} registradas / ${d['expected']} esperadas · ${d['plan_id'] == null ? 'Configuración' : 'Plan aprobado'}',
                  ),
                ),
            ],
          ),
        ],
        if (_history.isNotEmpty)
          ExpansionTile(
            title: const Text('Evaluaciones guardadas'),
            children: [
              for (final a in _history)
                ListTile(
                  title: Text(
                    '${a['snapshot']['start_date']} a ${a['snapshot']['end_date']}',
                  ),
                  subtitle: Text(
                    'v${a['snapshot']['configuration']['version']} · ${_stamp(a['created_at'])} UTC',
                  ),
                  onTap: () => setState(
                    () => _report = Map<String, dynamic>.from(
                      a['snapshot'] as Map,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _conversation() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (_contacts.isEmpty)
        const Text(
          'Necesitas un vínculo activo paciente–nutricionista para conversar.',
        ),
      DropdownButtonFormField<String>(
        initialValue: _peer,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Conversar con'),
        items: [
          for (final p in _contacts)
            DropdownMenuItem(
              value: p['id'] as String,
              child: Text(p['full_name']),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) {
                setState(() {
                  _peer = value;
                  _messages = [];
                });
                _thread();
              },
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: _busy || _peer == null ? null : () => _thread(),
            child: const Text('Actualizar mensajes'),
          ),
          if (_hasMore)
            TextButton(
              onPressed: _busy ? null : () => _thread(older: true),
              child: const Text('Mensajes anteriores'),
            ),
        ],
      ),
      for (final m in _messages)
        Align(
          alignment: m['sender_id'] == _owner
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Card(
            color: m['sender_id'] == _owner
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['sender_id'] == _owner ? 'Vos' : 'Tu contacto',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(m['content']),
                  Text(
                    '${_stamp(m['created_at'])} UTC',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      if (_messages.isEmpty && _peer != null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No hay mensajes cargados.'),
        ),
      TextField(
        controller: _text,
        enabled: !_busy,
        maxLength: 4000,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Mensaje'),
      ),
      FilledButton.icon(
        onPressed: _busy || _peer == null ? null : _send,
        icon: const Icon(Icons.send),
        label: const Text('Enviar mensaje'),
      ),
    ],
  );
}

class _WeightPainter extends CustomPainter {
  final List<double> values;
  _WeightPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minimum = values.reduce(math.min), maximum = values.reduce(math.max);
    final span = math.max(maximum - minimum, 1);
    final paint = Paint()
      ..color = const Color(0xff087f77)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = 8 + i * (size.width - 16) / (values.length - 1);
      final y =
          size.height - 8 - (values[i] - minimum) * (size.height - 16) / span;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WeightPainter oldDelegate) =>
      oldDelegate.values != values;
}
