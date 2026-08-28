import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/l10n/generated/app_localizations.dart';
import 'package:NEk0/models/channel.dart';
import 'package:NEk0/widgets/channel_tree.dart';

/// Wraps [ChannelTree] in the app's localization setup so tooltips/hints
/// resolve (they come from AppLocalizations, resolved as English in tests).
Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SizedBox(width: 360, height: 400, child: child)),
);

List<TsChannel> _channels() => const [
  TsChannel(id: 1, name: 'Lobby', parentId: 0, clientCount: 3, order: 0),
  TsChannel(id: 2, name: 'Gaming', parentId: 0, clientCount: 0, order: 1),
  TsChannel(id: 3, name: 'Shoutbox', parentId: 0, clientCount: 0, order: 2),
  TsChannel(id: 4, name: 'Nested', parentId: 2, clientCount: 1, order: 0),
];

void main() {
  testWidgets('renders root channels and skips nested until expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ChannelTree(channels: _channels(), onChannelTap: (_) {})),
    );
    expect(find.text('Lobby'), findsOneWidget);
    expect(find.text('Gaming'), findsOneWidget);
    expect(find.text('Shoutbox'), findsOneWidget);
    expect(find.text('Nested'), findsNothing);
  });

  testWidgets('search flattens and filters by name', (tester) async {
    await tester.pumpWidget(
      _wrap(ChannelTree(channels: _channels(), onChannelTap: (_) {})),
    );
    await tester.enterText(find.byType(TextField), 'shout');
    await tester.pumpAndSettle();
    expect(find.text('Shoutbox'), findsOneWidget);
    expect(find.text('Lobby'), findsNothing);
    expect(find.text('Gaming'), findsNothing);
  });

  testWidgets('a query with no matches shows the empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(ChannelTree(channels: _channels(), onChannelTap: (_) {})),
    );
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('sort toggle calls back and lets the parent re-sort', (
    tester,
  ) async {
    bool? requested;
    await tester.pumpWidget(
      _wrap(
        ChannelTree(
          channels: _channels(),
          onChannelTap: (_) {},
          sortAlphabetically: false,
          onToggleSort: (v) => requested = v,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.swap_vert));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
  });

  testWidgets('long-press toggles a favorite', (tester) async {
    int? tappedId;
    bool? fav;
    await tester.pumpWidget(
      _wrap(
        ChannelTree(
          channels: _channels(),
          onChannelTap: (_) {},
          onToggleFavorite: (id, f) {
            tappedId = id;
            fav = f;
          },
        ),
      ),
    );
    await tester.longPress(find.text('Gaming'));
    await tester.pumpAndSettle();
    expect(tappedId, 2);
    // Gaming was not favourited, so the toggle asks to favour it.
    expect(fav, isTrue);
  });

  testWidgets('favourited channels are marked with a star', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ChannelTree(
          channels: _channels(),
          onChannelTap: (_) {},
          favoriteChannelIds: const {2},
        ),
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
