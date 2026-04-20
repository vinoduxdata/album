import 'package:auto_route/auto_route.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/domain/services/asset.service.dart' as beta_asset_service;
import 'package:immich_mobile/domain/services/memory.service.dart';
import 'package:immich_mobile/domain/services/people.service.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart' as beta_asset_provider;
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/repositories/shared_space_api.repository.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:logging/logging.dart';

final deepLinkServiceProvider = Provider(
  (ref) => DeepLinkService(
    ref.watch(timelineFactoryProvider),
    ref.watch(beta_asset_provider.assetServiceProvider),
    ref.watch(remoteAlbumServiceProvider),
    ref.watch(driftMemoryServiceProvider),
    ref.watch(driftPeopleServiceProvider),
    ref.watch(sharedSpaceApiRepositoryProvider),
    ref.watch(currentUserProvider),
  ),
);

class DeepLinkService {
  static final Logger _log = Logger('DeepLinkService');

  final TimelineFactory _betaTimelineFactory;
  final beta_asset_service.AssetService _betaAssetService;
  final RemoteAlbumService _betaRemoteAlbumService;
  final DriftMemoryService _betaMemoryService;
  final DriftPeopleService _betaPeopleService;

  /// Fork-only: shared spaces are a Gallery feature with no Immich equivalent.
  final SharedSpaceApiRepository _sharedSpaceApiRepository;

  final UserDto? _currentUser;

  const DeepLinkService(
    this._betaTimelineFactory,
    this._betaAssetService,
    this._betaRemoteAlbumService,
    this._betaMemoryService,
    this._betaPeopleService,
    this._sharedSpaceApiRepository,
    this._currentUser,
  );

  DeepLink _handleColdStart(PageRouteInfo<dynamic> route, bool isColdStart) {
    return DeepLink([
      // Fork-only: cold-start landing is the fork's gallery-bottom-nav shell.
      if (isColdStart) const GalleryTabShellRoute(),
      route,
    ]);
  }

  Future<DeepLink> handleScheme(PlatformDeepLink link, WidgetRef ref, bool isColdStart) async {
    // get everything after the scheme, since Uri cannot parse path
    final intent = link.uri.host;
    final queryParams = link.uri.queryParameters;

    PageRouteInfo<dynamic>? deepLinkRoute = switch (intent) {
      "memory" => await _buildMemoryDeepLink(queryParams['id'] ?? ''),
      "asset" => await _buildAssetDeepLink(queryParams['id'] ?? '', ref),
      "album" => await _buildAlbumDeepLink(queryParams['id'] ?? ''),
      "space" => await _buildSpaceDeepLink(queryParams['id'] ?? ''),
      "people" => await _buildPeopleDeepLink(queryParams['id'] ?? ''),
      "activity" => await _buildActivityDeepLink(queryParams['albumId'] ?? ''),
      _ => null,
    };

    // Deep link resolution failed, safely handle it based on the app state
    if (deepLinkRoute == null) {
      if (isColdStart) {
        return DeepLink.defaultPath;
      }

      return DeepLink.none;
    }

    return _handleColdStart(deepLinkRoute, isColdStart);
  }

  Future<DeepLink> handleMyImmichApp(PlatformDeepLink link, WidgetRef ref, bool isColdStart) async {
    final path = link.uri.path;

    const uuidRegex = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
    final assetRegex = RegExp('/photos/($uuidRegex)');
    final albumRegex = RegExp('/albums/($uuidRegex)');
    final peopleRegex = RegExp('/people/($uuidRegex)');

    PageRouteInfo<dynamic>? deepLinkRoute;
    if (assetRegex.hasMatch(path)) {
      final assetId = assetRegex.firstMatch(path)?.group(1) ?? '';
      deepLinkRoute = await _buildAssetDeepLink(assetId, ref);
    } else if (albumRegex.hasMatch(path)) {
      final albumId = albumRegex.firstMatch(path)?.group(1) ?? '';
      deepLinkRoute = await _buildAlbumDeepLink(albumId);
    } else if (peopleRegex.hasMatch(path)) {
      final peopleId = peopleRegex.firstMatch(path)?.group(1) ?? '';
      deepLinkRoute = await _buildPeopleDeepLink(peopleId);
    } else if (path == "/memory") {
      deepLinkRoute = await _buildMemoryDeepLink(null);
    }

    // Deep link resolution failed, safely handle it based on the app state
    if (deepLinkRoute == null) {
      if (isColdStart) return DeepLink.defaultPath;
      return DeepLink.none;
    }

    return _handleColdStart(deepLinkRoute, isColdStart);
  }

  Future<PageRouteInfo?> _buildMemoryDeepLink(String? memoryId) async {
    List<DriftMemory> memories = [];

    if (memoryId == null) {
      if (_currentUser == null) {
        return null;
      }

      memories = await _betaMemoryService.getMemoryLane(_currentUser.id);
    } else {
      final memory = await _betaMemoryService.get(memoryId);
      if (memory != null) {
        memories = [memory];
      }
    }

    if (memories.isEmpty) {
      return null;
    }

    return DriftMemoryRoute(memories: memories, memoryIndex: 0);
  }

  Future<PageRouteInfo?> _buildAssetDeepLink(String assetId, WidgetRef ref) async {
    final asset = await _betaAssetService.getRemoteAsset(assetId);
    if (asset == null) {
      return null;
    }

    AssetViewer.setAsset(ref, asset);
    return AssetViewerRoute(
      initialIndex: 0,
      timelineService: _betaTimelineFactory.fromAssets([asset], TimelineOrigin.deepLink),
    );
  }

  Future<PageRouteInfo?> _buildAlbumDeepLink(String albumId) async {
    final album = await _betaRemoteAlbumService.get(albumId);

    if (album == null) {
      return null;
    }

    return RemoteAlbumRoute(album: album);
  }

  /// Fork-only: shared spaces are a Gallery feature with no Immich equivalent.
  Future<PageRouteInfo?> _buildSpaceDeepLink(String spaceId) async {
    if (spaceId.isEmpty) {
      return null;
    }

    try {
      // Verifies the space exists and is accessible to the current user before
      // we attempt to navigate. The space detail page only needs the id.
      await _sharedSpaceApiRepository.get(spaceId);
    } catch (error, stackTrace) {
      _log.warning('Failed to resolve space deep link for $spaceId', error, stackTrace);
      return null;
    }

    return SpaceDetailRoute(spaceId: spaceId);
  }

  Future<PageRouteInfo?> _buildActivityDeepLink(String albumId) async {
    final album = await _betaRemoteAlbumService.get(albumId);

    if (album == null || album.isActivityEnabled == false) {
      return null;
    }

    return DriftActivitiesRoute(album: album);
  }

  Future<PageRouteInfo?> _buildPeopleDeepLink(String personId) async {
    final person = await _betaPeopleService.get(personId);

    if (person == null) {
      return null;
    }

    return DriftPersonRoute(person: person);
  }
}
