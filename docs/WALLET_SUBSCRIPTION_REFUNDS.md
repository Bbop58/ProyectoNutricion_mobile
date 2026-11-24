# Devolución total de Premium IA

Versión 1.1.1+3. Cliente: Perfil → Devoluciones a wallet, o desde el comprobante
de una suscripción personal. Requiere conexión y un Premium vigente con pago
PayPal confirmado. Muestra el importe total, pide motivo y confirmación.

La solicitud no cancela Premium ni acredita saldo por sí sola. El superadmin
decide desde la web → Devoluciones a wallet. Aprobar vuelve a verificar el pago
con PayPal y realiza una transacción: crédito único a wallet, cierre del Premium,
auditoría y notificación. Rechazar conserva la suscripción y el saldo.

Actualizar estado y saldo refresca el Premium local y la wallet. Una aprobación
habilita Descargar comprobante PDF y Enviar al correo. El mismo documento aparece
en Mis comprobantes. El saldo puede pagar consultas y no se devuelve a PayPal.

Para probar se necesita comprar un Premium IA con PayPal Sandbox y verificar ese
pago. Las asignaciones sin cobro y los recibos sintéticos DEMO del seeder no
permiten devoluciones. Una solicitud rechazada no se vuelve a abrir para el mismo
período. Una suscripción vencida, cancelada o reemplazada no admite aprobación.

Pruebas móviles: 22 pruebas aprobadas en suscripciones/wallet/cola y flujo nuevo;
caso de red corregido y archivo de devoluciones final 2/2 aprobado. Son conjuntos
superpuestos. Análisis de archivos modificados sin incidencias.

APK de prueba: compilar con `flutter build apk --debug --no-pub
--dart-define=API_BASE_URL=https://backend-api-production-d40295b0.up.railway.app/api/v1`.
Se conserva la firma de desarrollo existente; no se cambian almacenamiento ni
colas pendientes. No representa una compilación release para tienda.
