import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "fs/promises";
import { join } from "path";
import { tmpdir } from "os";
import { pathToFileURL } from "url";

const resolverModuleUrl = pathToFileURL(
  "/home/matrix/nixconf/modules/nixos/scripts/bunjs/proxy/vpn-resolver.ts",
).href;

async function loadResolverWithVpnDir(vpnDir: string) {
  process.env.VPN_DIR = vpnDir;
  const mod = await import(
    `${resolverModuleUrl}?test=${Date.now()}-${Math.random()}`
  );
  mod.invalidateCache();
  return mod;
}

describe("vpn resolver basename preservation", () => {
  let fixtureDir = "";

  beforeEach(async () => {
    fixtureDir = await mkdtemp(join(tmpdir(), "vpn-resolver-"));

    await writeFile(
      join(fixtureDir, "us_wyoming.ovpn"),
      `client
remote us-wyoming-pf.privacy.network 1198
auth-user-pass
`,
    );
    await writeFile(
      join(fixtureDir, "uk_london.ovpn"),
      `client
remote uk-london.privacy.network 1198
auth-user-pass
`,
    );
    await writeFile(
      join(fixtureDir, "AirVPN GB London Alathfar.ovpn"),
      `client
remote gb-london.airvpn.example 1194
auth-user-pass
`,
    );
  });

  afterEach(async () => {
    delete process.env.VPN_DIR;
    if (fixtureDir) {
      await rm(fixtureDir, { recursive: true, force: true });
    }
  });

  test("keeps provider-style basenames readable while generating space-free slugs", async () => {
    const resolver = await loadResolverWithVpnDir(fixtureDir);
    const vpns = await resolver.listVpns();

    expect(vpns).toEqual([
      expect.objectContaining({
        displayName: "AirVPN GB London Alathfar",
        slug: "AirVPNGBLondonAlathfar",
        countryCode: "GB",
        flag: "🇬🇧",
      }),
      expect.objectContaining({
        displayName: "uk london",
        slug: "uklondon",
        countryCode: "UK",
        flag: "🇬🇧",
      }),
      expect.objectContaining({
        displayName: "us wyoming",
        slug: "uswyoming",
        countryCode: "US",
        flag: "🇺🇸",
      }),
    ]);
  });

  test("parses AirVPN-style fields without regressing provider-style names", async () => {
    const resolver = await loadResolverWithVpnDir(fixtureDir);

    expect(
      resolver.parseVpnFields("AirVPN GB London Alathfar", [
        { name: "country", regex: "\\b([A-Z]{2})\\b", position: 1 },
        {
          name: "city",
          regex: "\\b[A-Z]{2}\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*)\\b",
          position: 1,
        },
        {
          name: "server",
          regex:
            "\\b[A-Z]{2}\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+([A-Z][a-z]+)\\b",
          position: 1,
        },
      ]),
    ).toEqual({
      country: "GB",
      city: "London Alathfar",
      server: "Alathfar",
    });

    expect(
      resolver.parseVpnFields("us wyoming", [
        { name: "country", regex: "\\b([A-Z]{2})\\b", position: 1 },
      ]),
    ).toEqual({});
  });
});
