import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'parse.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class Shot {
  final String id;
  final String photo;
  String status = 'reading'; // reading | added | review | failed
  String label = 'Reading…';
  String? itemId;
  String cat = 'other';
  Shot(this.id, this.photo);
}

/// Background queue: every photo is read on the phone while you keep shooting.
class CaptureQueue extends ChangeNotifier {
  final List<Shot> shots = [];
  String? saveTo;

  void setSaveTo(String? id) {
    saveTo = id;
    notifyListeners();
  }
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<void> add(String rawPath) async {
    final kept = await store.keepPhoto(rawPath);
    final s = Shot(store.newId('s'), kept);
    shots.insert(0, s);
    notifyListeners();
    final loc = saveTo;
    try {
      final res = await _recognizer.processImage(InputImage.fromFilePath(kept));
      final p = parseLabel(res.text);
      s.cat = p.cat;
      if (p.confident && p.name != null) {
        final it = store.addItem(Item(
          id: store.newId('i'),
          name: p.name!,
          cat: p.cat,
          qty: p.qty ?? 1,
          loc: loc,
          specs: p.specs,
          photos: [kept],
          source: 'Read from the label on the phone',
        ));
        s.status = 'added';
        s.label = 'Added';
        s.itemId = it.id;
      } else {
        store.review.add(ReviewEntry(
          id: store.newId('r'),
          photo: kept,
          loc: loc,
          guess: p.name ?? '',
          cat: p.cat,
          ocrText: res.text,
          reason: p.reason,
          qty: p.qty ?? 1,
          specs: p.specs,
        ));
        store.changed();
        s.status = 'review';
        s.label = 'Review';
      }
    } catch (e) {
      store.review.add(ReviewEntry(id: store.newId('r'), photo: kept, loc: loc, reason: 'Couldn’t read this photo. Tell me what it is.'));
      store.changed();
      s.status = 'review';
      s.label = 'Review';
    }
    notifyListeners();
  }
}

final captureQueue = CaptureQueue();

class CaptureScreen extends StatelessWidget {
  final VoidCallback onGoReview;
  const CaptureScreen({super.key, required this.onGoReview});

  Future<void> _shootLoop(BuildContext context) async {
    final picker = ImagePicker();
    // Keeps reopening the camera until you back out, so you can walk and shoot.
    while (true) {
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
      if (x == null) break;
      captureQueue.add(x.path); // not awaited: reading happens in the background
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([captureQueue, store]),
      builder: (context, _) {
        final shots = captureQueue.shots;
        final added = shots.where((s) => s.status == 'added').length;
        final rev = shots.where((s) => s.status == 'review').length;
        return SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            const Text('Capture', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            const Text('Shoot tools or their case labels. The phone reads each one while you keep going.', style: TextStyle(color: kText2, fontSize: 14, height: 1.4)),
            const SizedBox(height: 16),
            Material(
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final id = await pickLocation(context, title: 'Save photos to…');
                  if (id != null) {
                    captureQueue.setSaveTo(id.isEmpty ? null : id);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.place_rounded, color: kAmber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('SAVING TO · TAP TO CHANGE', style: sectionLabel),
                        const SizedBox(height: 2),
                        Text(store.path(captureQueue.saveTo), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: () => _shootLoop(context),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kText, width: 5)),
                  padding: const EdgeInsets.all(7),
                  child: Container(
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: kAmber),
                    child: const Icon(Icons.photo_camera_rounded, color: Colors.black, size: 40),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(child: Text('Tap to start shooting. Back out of the camera when you’re done.', textAlign: TextAlign.center, style: TextStyle(color: kText2, fontSize: 13))),
            const SizedBox(height: 24),
            if (shots.isNotEmpty) ...[
              Row(children: [
                Text('${shots.length} SHOTS · $added ADDED · $rev TO REVIEW', style: sectionLabel),
                const Spacer(),
                if (rev > 0) TextButton(onPressed: onGoReview, child: const Text('Review')),
              ]),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
                children: [
                  for (final s in shots.take(40))
                    GestureDetector(
                      onTap: () {
                        if (s.status == 'added' && s.itemId != null) {
                          Navigator.of(context).pushNamed('/item', arguments: s.itemId);
                        } else if (s.status == 'review') {
                          onGoReview();
                        }
                      },
                      child: Column(children: [
                        ToolThumb(photo: s.photo, cat: s.cat, size: 72),
                        const SizedBox(height: 4),
                        Text(s.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: s.status == 'added' ? kBlue : (s.status == 'review' ? kAmber : kText2),
                            )),
                      ]),
                    ),
                ],
              ),
            ],
          ]),
        );
      },
    );
  }
}
