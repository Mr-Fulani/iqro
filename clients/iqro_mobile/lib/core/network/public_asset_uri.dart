/// Local media is confined to the configured API origin and /media/ path.
Uri resolvePublicAssetUri(String value, Uri apiBase) => apiBase.resolve(value);

bool isApprovedPublicAssetUri(
  Uri uri, {
  required Set<String> allowedHosts,
  Uri? localApiBase,
}) {
  if (uri.userInfo.isNotEmpty || uri.hasFragment) return false;
  if (uri.scheme == 'https' && !uri.hasPort && allowedHosts.contains(uri.host)) {
    return true;
  }
  return localApiBase != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.origin == localApiBase.origin &&
      uri.path.startsWith('/media/') &&
      !uri.pathSegments.contains('..') &&
      !uri.hasQuery;
}
