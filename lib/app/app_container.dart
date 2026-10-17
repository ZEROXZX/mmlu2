import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/token_store.dart';
import '../core/domain/domain_store.dart';
import '../core/network/api_client.dart';
import '../data/api/api_service.dart';
import '../data/repo/app_repo.dart';
import '../data/repo/content_repo.dart';
import '../data/repo/member_repo.dart';
import '../data/service/download_service.dart';
import '../data/service/download_store.dart';
import '../data/service/download_task.dart';
import '../data/service/hls_proxy.dart';
import '../data/service/resource_service.dart';
import '../data/service/stream_service.dart';

/// 依赖容器（轻量手写 DI，等价于 App 的 Koin 模块）。
///
/// 对应 Koin ApplicationModule.kt (Lg/n/d/t3;) 的 OkHttp/Retrofit 提供者。
class AppContainer {
  AppContainer._({
    required this.prefs,
    required this.tokenStore,
    required this.domainStore,
    required this.apiClient,
    required this.apiService,
    required this.memberRepo,
    required this.appRepo,
    required this.contentRepo,
    required this.resourceService,
    required this.streamService,
    required this.downloadStore,
    required this.downloadService,
    required this.downloadManager,
    required this.hlsProxy,
  });

  final SharedPreferences prefs;
  final TokenStore tokenStore;
  final DomainStore domainStore;
  final ApiClient apiClient;
  final ApiService apiService;
  final MemberRepo memberRepo;
  final AppRepo appRepo;
  final ContentRepo contentRepo;
  final ResourceService resourceService;
  final StreamService streamService;
  final DownloadStore downloadStore;
  final DownloadService downloadService;
  final DownloadManager downloadManager;
  final HlsProxy hlsProxy;

  static Future<AppContainer> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenStore = TokenStore(prefs);
    final domainStore = DomainStore(prefs);
    final client = ApiClient(tokenStore: tokenStore, domainStore: domainStore);
    final api = ApiService(client);
    final resources = ResourceService(domainStore);
    final streams = StreamService(domains: domainStore, tokenStore: tokenStore);
    final downloadStore = DownloadStore(prefs);
    final downloads = DownloadService();
    final downloadManager = DownloadManager(
      streams: streams,
      resources: resources,
      store: downloadStore,
      service: downloads,
      prefs: prefs,
    );
    return AppContainer._(
      prefs: prefs,
      tokenStore: tokenStore,
      domainStore: domainStore,
      apiClient: client,
      apiService: api,
      memberRepo: MemberRepo(api, tokenStore),
      appRepo: AppRepo(api, client),
      contentRepo: ContentRepo(api),
      resourceService: resources,
      streamService: streams,
      downloadStore: downloadStore,
      downloadService: downloads,
      downloadManager: downloadManager,
      hlsProxy: HlsProxy(streams),
    );
  }
}
