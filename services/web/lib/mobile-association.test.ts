import assert from "node:assert/strict";
import test from "node:test";

import {
  androidAssetLinks,
  appleAppSiteAssociation,
} from "./mobile-association.ts";

const releaseFingerprint =
  "AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA";

test("staging associates the connected-device debug signature only on staging", () => {
  const staging = androidAssetLinks({ siteUrl: "https://staging.iqro.forum" });
  const production = androidAssetLinks({ siteUrl: "https://iqro.forum" });

  assert.equal(staging.length, 1);
  assert.equal(staging[0]?.target.package_name, "forum.iqro.app");
  assert.equal(staging[0]?.target.sha256_cert_fingerprints.length, 1);
  assert.deepEqual(production, []);
});

test("production publishes only validated configured Android fingerprints", () => {
  const result = androidAssetLinks({
    siteUrl: "https://iqro.forum",
    configuredFingerprints: `not-a-fingerprint, ${releaseFingerprint}`,
  });

  assert.deepEqual(result[0]?.target.sha256_cert_fingerprints, [releaseFingerprint]);
});

test("Apple association exposes only the IQRO bundle and Dua paths", () => {
  const result = appleAppSiteAssociation({
    configuredApplicationIdentifiers:
      "INVALID, A1B2C3D4E5.forum.iqro.app",
  });

  assert.deepEqual(result, {
    applinks: {
      apps: [],
      details: [
        {
          appID: "A1B2C3D4E5.forum.iqro.app",
          paths: [
            "/dua/*",
            "/ru/dua/*",
            "/en/dua/*",
            "/ar/dua/*",
            "/tr/dua/*",
          ],
        },
      ],
    },
  });
});
