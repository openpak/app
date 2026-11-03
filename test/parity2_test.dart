import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpak/api.dart';
import 'package:openpak/rewards_glance.dart';
import 'package:openpak/theme.dart';
import 'package:openpak/title_art.dart';
import 'package:openpak/updater.dart';

import 'localized.dart';
import 'rewards_test.dart' show fullView;

http.Response _json(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

void main() {
  test('every account in the API may carry its picture', () {
    expect(BlockedAccount.fromJson({'account_id': 'a', 'display_name': 'A', 'avatar_url': '/media/avatars/a/256'}).avatarUrl, isNotNull);
    expect(Invitation.fromJson({'invitation_id': 'i', 'from': 'A', 'from_avatar_url': '/media/avatars/a/256', 'expires_at': '2030-01-01T00:00:00Z'}).fromAvatarUrl, isNotNull);
    expect(VoiceMember.fromJson({'account_id': 'a', 'avatar_url': '/m'}).avatarUrl, '/m');
    expect(Friend.fromJson({'account_id': 'a', 'display_name': 'A', 'avatar_url': '/m'}).avatarUrl, '/m');
  });

  test('a title carries its art, empty when it has none', () {
    expect(CatalogItem.fromJson({'id': 1, 'name': 'X', 'art_url': '/titles/icon/0100'}).artUrl, '/titles/icon/0100');
    expect(CatalogItem.fromJson({'id': 1, 'name': 'X'}).artUrl, isEmpty);
  });

  testWidgets('a title without art draws its console mark, never a broken image', (tester) async {
    final api = OpenPakApi(baseUrl: 'https://openpak.test');
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: Scaffold(body: SizedBox(width: 100, height: 100, child: TitleArt(api: api, item: CatalogItem(id: '1', kind: 'title', name: 'X', console: 'Wii')))),
    ));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Rewards card shows what is ready and the Account tab count follows it', (tester) async {
    final view = fullView();
    final api = OpenPakApi(baseUrl: 'https://openpak.test', token: 't', client: MockClient((_) async => _json(view)));
    final glance = RewardsGlance();
    await tester.pumpWidget(localizedApp(
      theme: openPakLight(),
      home: Scaffold(body: Column(children: [RewardsSummaryCard(api: api, glance: glance)])),
    ));
    expect(find.text('Rewards'), findsNothing); // nothing before it is known
    await tester.runAsync(() => glance.load(api));
    await tester.pump();
    expect(find.text('Rewards'), findsOneWidget);
    expect(find.textContaining('Pak Points'), findsOneWidget);
    expect(glance.ready, view['ready']);
  });

  test('a v0.24.0 install is offered v0.25.x', () {
    expect(Version.parse('0.25.2')! > Version.parse('0.24.0')!, isTrue);
    expect(Version.parse('v0.25.2')! > Version.parse('0.25.1')!, isTrue);
    expect(Version.parse('0.25.2')! > Version.parse('0.25.2')!, isFalse);
  });
}
