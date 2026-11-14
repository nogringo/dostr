import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:dostr_flutter/l10n/app_localizations.dart';
import 'package:qr/qr.dart';

class NostrConnectDialogView extends StatelessWidget {
  final String nostrConnectURL;

  const NostrConnectDialogView({super.key, required this.nostrConnectURL});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: Text(AppLocalizations.of(context)!.nostrConnectUrl),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
          child: AspectRatio(
            aspectRatio: 1,
            child: _QrCodeView(data: nostrConnectURL),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: nostrConnectURL));
            },
            child: Text(AppLocalizations.of(context)!.copy),
          ),
        ],
      ),
    );
  }
}

class _QrCodeView extends StatelessWidget {
  final String data;

  const _QrCodeView({required this.data});

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.low,
      ),
    );
    return CustomPaint(size: Size.infinite, painter: _QrCodePainter(image));
  }
}

class _QrCodePainter extends CustomPainter {
  // ISO/IEC 18004 requires a quiet zone of at least 4 modules.
  static const _quietZone = 4;

  final QrImage image;

  _QrCodePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.shortestSide / (count + 2 * _quietZone);
    final path = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          path.addRect(
            Rect.fromLTWH(
              (col + _quietZone) * module,
              (row + _quietZone) * module,
              module,
              module,
            ),
          );
        }
      }
    }
    canvas.drawPath(path, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_QrCodePainter oldDelegate) => oldDelegate.image != image;
}
