// Background removal for tool photos, on the phone (Google ML Kit subject
// segmentation). The cutout is what floats out of the drawer.

import 'dart:io';

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

import 'models.dart';
import 'store.dart';

SubjectSegmenter? _seg;
final Set<String> _busy = {};

Future<String?> makeCutout(String photoPath) async {
  try {
    _seg ??= SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundConfidenceMask: false,
        enableForegroundBitmap: true,
        enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
      ),
    );
    final res = await _seg!.processImage(InputImage.fromFilePath(photoPath));
    final bytes = res.foregroundBitmap;
    if (bytes == null || bytes.isEmpty) return null;
    final out = '${store.photoDir.path}/${store.newId('cut')}.png';
    await File(out).writeAsBytes(bytes);
    return out;
  } catch (_) {
    return null; // keep the plain photo if cutout isn't available on this phone
  }
}

/// Makes a cutout for an item's first photo if it doesn't have one yet.
Future<void> ensureCutout(Item it) async {
  if (it.cutout != null && File(it.cutout!).existsSync()) return;
  if (it.photos.isEmpty || _busy.contains(it.id)) return;
  _busy.add(it.id);
  try {
    final c = await makeCutout(it.photos.first);
    if (c != null) {
      it.cutout = c;
      store.changed();
    }
  } finally {
    _busy.remove(it.id);
  }
}
