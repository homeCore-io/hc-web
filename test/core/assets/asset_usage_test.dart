import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/assets_api.dart';
import 'package:hc_web/core/assets/asset_usage.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/skin_document.dart';

/// What would break if you deleted this.
///
/// Core does not reference-count, so nothing stops a deletion — which makes
/// *showing the consequence first* the only thing standing between a manager
/// page and a wallpaper vanishing off a dashboard with no warning.
///
/// The mechanism is a text search over the serialised document, chosen because
/// an asset is referenced by its address and an address embeds the id. That
/// means it finds every place without knowing any of them, which is the
/// property worth pinning: the four that store one today were each added
/// separately, and a fifth should not need this file changed.

final _id = 'a' * 64;
final _other = 'b' * 64;

AssetRef _asset(String id, {String? group}) => AssetRef(
      id: id,
      contentType: 'image/png',
      size: 100,
      name: 'wall.png',
      group: group,
    );

DashboardDefinition _dashboard(
  String name, {
  DashboardBackground? background,
  List<DashboardWidgetModel> widgets = const [],
}) =>
    DashboardDefinition(
      id: name.toLowerCase(),
      name: name,
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: widgets,
      layouts: const [],
      background: background,
    );

DashboardWidgetModel _widget(Map<String, dynamic> config) =>
    DashboardWidgetModel(
      id: 'w',
      type: 'image',
      title: 'A picture',
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: config,
    );

void main() {
  group('finding an asset', () {
    test('in a page background', () {
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [
          _dashboard('Getting Started',
              background: DashboardBackground(image: assetUrl(_id))),
        ],
        skins: const [],
      );
      expect(usage[_id]!.dashboards, ['Getting Started']);
      expect(usage[_id]!.summary, 'Used by Getting Started');
    });

    test('in a widget config', () {
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [
          _dashboard('Kitchen', widgets: [
            _widget({'url': assetUrl(_id)})
          ]),
        ],
        skins: const [],
      );
      expect(usage[_id]!.dashboards, ['Kitchen']);
    });

    test("in a card's style, which is nested two levels down", () {
      // The reason this searches text rather than walking a schema: the card
      // picture lives inside a widget's config under `style`, and every new
      // place would otherwise need this file taught about it.
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [
          _dashboard('Hall', widgets: [
            _widget({
              'style': {'image': assetUrl(_id), 'blur': 4}
            })
          ]),
        ],
        skins: const [],
      );
      expect(usage[_id]!.dashboards, ['Hall']);
    });

    test('in a skin, as a font', () {
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: const [],
        skins: [
          SkinDocument(
            id: 's',
            name: 'Evening',
            base: 'midnight',
            seeds: const {},
            overrides: {'font.Fraunces': assetUrl(_id)},
          ),
        ],
      );
      expect(usage[_id]!.skins, ['Evening']);
      expect(usage[_id]!.summary, 'Used by Evening');
    });

    test('in several places at once', () {
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [
          _dashboard('One',
              background: DashboardBackground(image: assetUrl(_id))),
          _dashboard('Two',
              background: DashboardBackground(image: assetUrl(_id))),
          _dashboard('Three',
              background: DashboardBackground(image: assetUrl(_id))),
        ],
        skins: const [],
      );
      expect(usage[_id]!.count, 3);
      expect(usage[_id]!.summary, 'Used by One, Two and 1 more');
    });
  });

  group('not finding one', () {
    test('an asset nothing points at says so', () {
      // The one that is safe to delete, and the manager says it out loud.
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [_dashboard('Empty')],
        skins: const [],
      );
      expect(usage[_id]!.isEmpty, isTrue);
      expect(usage[_id]!.summary, isNull);
    });

    test('a different asset is not a match', () {
      final usage = assetUsage(
        assets: [_asset(_id), _asset(_other)],
        dashboards: [
          _dashboard('One',
              background: DashboardBackground(image: assetUrl(_other))),
        ],
        skins: const [],
      );
      expect(usage[_id]!.isEmpty, isTrue);
      expect(usage[_other]!.dashboards, ['One']);
    });

    test('a pasted external address is nobody\'s asset', () {
      final usage = assetUsage(
        assets: [_asset(_id)],
        dashboards: [
          _dashboard('One',
              background: const DashboardBackground(
                  image: 'https://house.lan/wall.png')),
        ],
        skins: const [],
      );
      expect(usage[_id]!.isEmpty, isTrue);
    });
  });

  test('every asset gets an answer, used or not', () {
    // The manager indexes by id and would throw on a missing key.
    final usage = assetUsage(
      assets: [_asset(_id), _asset(_other)],
      dashboards: const [],
      skins: const [],
    );
    expect(usage.keys.toSet(), {_id, _other});
  });
}
