import 'vr_content_provider.dart';

/// Public deployment configuration only. Firebase credentials are obtained
/// from the account session; no token or secret belongs in these defines.
VrContentProvider configuredContentProvider(VrContentSource source) {
  final (catalog, access, hosts) = switch (source) {
    VrContentSource.emxi => (
      const String.fromEnvironment('VRLIZATE_EMXI_CATALOG_URL'),
      const String.fromEnvironment('VRLIZATE_EMXI_ACCESS_URL'),
      const String.fromEnvironment('VRLIZATE_EMXI_MEDIA_HOSTS'),
    ),
    VrContentSource.gigmeout => (
      const String.fromEnvironment('VRLIZATE_GIGMEOUT_CATALOG_URL'),
      const String.fromEnvironment('VRLIZATE_GIGMEOUT_ACCESS_URL'),
      const String.fromEnvironment('VRLIZATE_GIGMEOUT_MEDIA_HOSTS'),
    ),
    VrContentSource.cyberneom => (
      const String.fromEnvironment('VRLIZATE_CYBERNEOM_CATALOG_URL'),
      const String.fromEnvironment('VRLIZATE_CYBERNEOM_ACCESS_URL'),
      const String.fromEnvironment('VRLIZATE_CYBERNEOM_MEDIA_HOSTS'),
    ),
  };
  VrContentEndpoint? endpoint;
  if (catalog.isNotEmpty && access.isNotEmpty && hosts.isNotEmpty) {
    try {
      endpoint = VrContentEndpoint(
        catalog: Uri.parse(catalog),
        access: Uri.parse(access),
        mediaHosts: hosts.split(',').map((host) => host.trim()).toSet(),
      );
    } on FormatException {
      // Invalid deployment configuration stays unavailable, never falls back
      // to another application's project or an inferred public endpoint.
    }
  }
  return VrContentProvider(source: source, endpoint: endpoint);
}
