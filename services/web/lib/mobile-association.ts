const STAGING_ANDROID_DEBUG_FINGERPRINT =
  "B2:47:BA:F0:4C:D7:B7:0A:B9:06:9B:43:3D:17:73:11:7E:3C:2B:09:1B:4E:B7:3C:28:E5:4E:35:C4:84:87:2A";

const ANDROID_FINGERPRINT_PATTERN = /^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$/;
const APPLE_APPLICATION_IDENTIFIER_PATTERN = /^[A-Z0-9]{10}\.forum\.iqro\.app$/i;

function configuredValues(value: string | undefined): string[] {
  return (value ?? "")
    .split(/[\s,]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function configuredHostname(siteUrl: string | undefined): string {
  if (!siteUrl?.trim()) return "";
  try {
    return new URL(siteUrl).hostname.toLowerCase();
  } catch {
    return "";
  }
}

export function androidAssetLinks({
  siteUrl = process.env.SITE_URL,
  configuredFingerprints = process.env.ANDROID_APP_LINK_SHA256_CERT_FINGERPRINTS,
}: {
  siteUrl?: string;
  configuredFingerprints?: string;
} = {}) {
  const fingerprints = new Set(
    configuredValues(configuredFingerprints)
      .map((item) => item.toUpperCase())
      .filter((item) => ANDROID_FINGERPRINT_PATTERN.test(item)),
  );
  if (configuredHostname(siteUrl) === "staging.iqro.forum") {
    fingerprints.add(STAGING_ANDROID_DEBUG_FINGERPRINT);
  }
  if (fingerprints.size === 0) return [];
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: "forum.iqro.app",
        sha256_cert_fingerprints: [...fingerprints],
      },
    },
  ];
}

export function appleAppSiteAssociation({
  configuredApplicationIdentifiers =
    process.env.APPLE_APP_LINK_APPLICATION_IDENTIFIERS,
}: {
  configuredApplicationIdentifiers?: string;
} = {}) {
  const applicationIdentifiers = [
    ...new Set(
      configuredValues(configuredApplicationIdentifiers)
        .filter((item) => APPLE_APPLICATION_IDENTIFIER_PATTERN.test(item)),
    ),
  ];
  return {
    applinks: {
      apps: [],
      details: applicationIdentifiers.map((appID) => ({
        appID,
        paths: [
          "/dua/*",
          "/ru/dua/*",
          "/en/dua/*",
          "/ar/dua/*",
          "/tr/dua/*",
        ],
      })),
    },
  };
}
