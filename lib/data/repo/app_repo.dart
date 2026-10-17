import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/domain/domain_store.dart';
import '../../core/network/api_client.dart';
import '../api/api_service.dart';
import '../models/app_info_response.dart';
import '../models/cdn_host_response.dart';

/// 应用配置/域名仓库。
class AppRepo {
  AppRepo(this._api, this._client);

  final ApiService _api;
  final ApiClient _client;

  Future<AppInfoResponse> appInfo() => _api.appInfo();

  Future<Object?> startup() => _api.startup();

  /// 拉取并解密 host.txt，返回明文 JSON 字符串（可自行 jsonDecode）。
  Future<String> fetchHostTxt() => _client.fetchAndDecryptHostTxt();

  /// 拉取 CDN 域名列表（AppApi @Url 动态 URL）。
  ///
  /// 调用方需提供完整 URL（通常由启动流程构造）。
  Future<CdnHostResponse> getCdnDomainHost(String url) async {
    final res = await _client.dio.get(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final data = res.data;
    if (data is Map) {
      return CdnHostResponse.fromJson(Map<String, dynamic>.from(data));
    }
    return CdnHostResponse();
  }

  /// 从 CdnHostResponse 择优写入域名（简化：取各列表首个有效项）。
  Future<void> applyCdnHosts(CdnHostResponse r) async {
    String? first(List<DomainTestBean>? l) {
      if (l == null) return null;
      for (final b in l) {
        if (b.isValid && (b.url?.isNotEmpty ?? false)) return b.url;
      }
      return null;
    }

    final api = first(r.api);
    final comic = first(r.comic);
    final fiction = first(r.fiction);
    final img = first(r.img);
    final stream = first(r.stream);
    if (api == null || comic == null || fiction == null || img == null || stream == null) {
      return;
    }
    final streamBean = r.stream!.firstWhere((b) => b.isValid && b.url == stream);
    await _client.domainStore.apply(
      api: api,
      comic: comic,
      fiction: fiction,
      img: img,
      stream: stream,
      comicReferer: r.comic?.firstWhere((b) => b.url == comic).referer ?? '',
      imgReferer: r.img?.firstWhere((b) => b.url == img).referer ?? '',
      streamHostUrl: streamBean.hostUrl ?? '',
      streamChain: streamBean.chain ?? '',
      streamCc: streamBean.cc ?? '',
    );
  }

  /// 便捷方法：直接设置单一域名类型。
  Future<void> setDomain(DomainType t, String url) =>
      _client.domainStore.set(t, url);

  /// 引导：拉取 host.txt（解密）→ 择优写入 5 类域名与流媒体线路。
  ///
  /// 返回是否成功写入至少一项。失败时保留 [DomainStore] 的静态默认值。
  Future<bool> bootstrapDomains() async {
    try {
      final txt = await fetchHostTxt();
      final obj = jsonDecode(txt);
      if (obj is! Map) return false;
      final r = CdnHostResponse.fromJson(obj.cast<String, dynamic>());

      String? first(List<DomainTestBean>? l) {
        if (l == null) return null;
        for (final b in l) {
          final u = b.url;
          if (u != null && u.isNotEmpty) return u;
        }
        return null;
      }

      var applied = false;
      Future<void> setIf(DomainType t, String? u) async {
        if (u != null && u.isNotEmpty) {
          await _client.domainStore.set(t, u);
          applied = true;
        }
      }

      await setIf(DomainType.apiData, first(r.api));
      await setIf(DomainType.apiComic, first(r.comic));
      await setIf(DomainType.apiFiction, first(r.fiction));
      await setIf(DomainType.apiImg, first(r.img));

      final streams = r.stream;
      if (streams != null) {
        for (final b in streams) {
          final u = b.url;
          if (u != null && u.isNotEmpty) {
            await _client.domainStore.setStreamLine(
              fetchUrl: u,
              tsUrl: b.hostUrl ?? _client.domainStore.streamTsUrl,
              chain: (b.chain?.isNotEmpty ?? false)
                  ? b.chain!
                  : _client.domainStore.streamChain,
            );
            applied = true;
            break;
          }
        }
      }
      return applied;
    } catch (_) {
      return false;
    }
  }
}
