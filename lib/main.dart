import 'package:flutter/material.dart';

import 'account.dart';
import 'capture.dart';
import 'home.dart';
import 'item.dart';
import 'models.dart';
import 'review.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  store.load();
  account.init();
  void maybeSync() {
    if (store.loaded && account.signedIn && !sync.on && !sync.busy) sync.start();
    if (!account.signedIn && sync.on) sync.stop();
  }
  store.addListener(maybeSync);
  account.addListener(maybeSync);
  runApp(const ToolInventoryApp());
}

class ToolInventoryApp extends StatelessWidget {
  const ToolInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tool Inventory',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      // Keep every screen, sheet and button clear of Android's back/home/recents
      // buttons and the gesture bar, in portrait and landscape.
      builder: (context, child) => ColoredBox(color: kBg, child: SafeArea(top: false, child: child ?? const SizedBox())),
      home: const Shell(),
      onGenerateRoute: (s) {
        if (s.name == '/item') {
          return MaterialPageRoute(builder: (_) => ItemScreen(id: s.arguments as String));
        }
        return null;
      },
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _go(int t) => setState(() => _tab = t);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: kAmber)));
        }
        final pages = [
          HomeScreen(onGoReview: () => _go(3), onGoCapture: () => _go(2)),
          const PhotosScreen(),
          CaptureScreen(onGoReview: () => _go(3)),
          const ReviewScreen(),
        ];
        return Scaffold(
          body: IndexedStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _go,
            destinations: [
              const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded, color: kAmber), label: 'Inventory'),
              const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded, color: kAmber), label: 'Photos'),
              const NavigationDestination(icon: Icon(Icons.photo_camera_outlined), selectedIcon: Icon(Icons.photo_camera_rounded, color: kAmber), label: 'Capture'),
              NavigationDestination(
                icon: Badge(isLabelVisible: store.review.isNotEmpty, label: Text('${store.review.length}'), backgroundColor: kAmber, textColor: Colors.black, child: const Icon(Icons.inbox_outlined)),
                selectedIcon: const Icon(Icons.inbox_rounded, color: kAmber),
                label: 'Review',
              ),
            ],
          ),
        );
      },
    );
  }
}

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});
  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  String _cat = 'all';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.items.where((i) => _cat == 'all' || i.cat == _cat).toList().reversed.toList();
        return SafeArea(
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${list.length} items', style: const TextStyle(color: kText2, fontSize: 13)),
                  const Text('Photos', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final c in ['all', ...kCats])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c == 'all' ? 'All' : kCatLabels[c]!),
                            selected: _cat == c,
                            onSelected: (_) => setState(() => _cat = c),
                            selectedColor: kAmber,
                            labelStyle: TextStyle(color: _cat == c ? Colors.black : kText),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final it in list)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed('/item', arguments: it.id),
                      child: LayoutBuilder(
                        builder: (_, c) => ToolThumb(photo: it.photos.isNotEmpty ? it.photos.first : null, cat: it.cat, size: c.maxWidth, radius: 6),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}
