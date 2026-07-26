import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, writeFile } from "fs/promises";
import { join } from "path";
import { tmpdir } from "os";

import {
  inspectOpenVpnAuth,
  patchOpenVpnAuthInPlace,
} from "./openvpn-auth-patching";
import {
  AUTH_PASSWORD,
  openVpnAuthFixtures,
  type OpenVpnAuthFixture,
} from "./test-fixtures/openvpn-auth-patching";
import { referencePatchOpenVpnAuthFixture } from "./test-support/openvpn-auth-patching-reference";

async function writeFixture(
  fixtureDir: string,
  fixture: OpenVpnAuthFixture,
): Promise<string> {
  const ovpnPath = join(fixtureDir, fixture.ovpnFileName);
  await writeFile(ovpnPath, fixture.ovpnContent);

  if (fixture.authFileName && fixture.authFileContent !== undefined) {
    await writeFile(
      join(fixtureDir, fixture.authFileName),
      fixture.authFileContent,
    );
  }

  return ovpnPath;
}

function getAuthFileContent(fixture: OpenVpnAuthFixture): string | undefined {
  return fixture.authFileContent;
}

describe("openvpn auth patching helper", () => {
  let fixtureDir = "";

  beforeEach(async () => {
    fixtureDir = await mkdtemp(join(tmpdir(), "openvpn-auth-patching-"));
  });

  afterEach(async () => {
    if (fixtureDir) {
      await rm(fixtureDir, { recursive: true, force: true });
    }
  });

  test("matches the contract classifier for all fixtures", () => {
    for (const fixture of Object.values(
      openVpnAuthFixtures,
    ) as OpenVpnAuthFixture[]) {
      expect(
        inspectOpenVpnAuth({
          ovpnFileName: fixture.ovpnFileName,
          ovpnContent: fixture.ovpnContent,
          authFileContent: getAuthFileContent(fixture),
          username: "vpn-user",
          password: AUTH_PASSWORD,
        }),
      ).toEqual(
        referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD, "vpn-user"),
      );
    }
  });

  test("embeds bare auth-user-pass credentials inline and stays idempotent", async () => {
    const ovpnPath = await writeFixture(
      fixtureDir,
      openVpnAuthFixtures.bareAuthUserPass,
    );

    const firstPass = await patchOpenVpnAuthInPlace({
      ovpnPath,
      username: "vpn-user",
      password: AUTH_PASSWORD,
    });

    expect(firstPass).toEqual(
      referencePatchOpenVpnAuthFixture(
        openVpnAuthFixtures.bareAuthUserPass,
        AUTH_PASSWORD,
        "vpn-user",
      ),
    );
    expect(await readFile(ovpnPath, "utf-8")).toBe(
      firstPass.patchedOvpnContent,
    );

    const secondPass = await patchOpenVpnAuthInPlace({
      ovpnPath,
      username: "vpn-user",
      password: AUTH_PASSWORD,
    });

    expect(secondPass.classification).toBe("inline-auth-user-pass");
    expect(secondPass.changed).toBe(false);
  });

  test("migrates referenced username-only auth into inline credentials and deletes the sidecar", async () => {
    const fixture = openVpnAuthFixtures.referencedUsernameOnly;
    const ovpnPath = await writeFixture(fixtureDir, fixture);
    const authPath = join(fixtureDir, fixture.authFileName!);

    const result = await patchOpenVpnAuthInPlace({
      ovpnPath,
      password: AUTH_PASSWORD,
    });

    expect(result).toEqual(
      referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD, "vpn-user"),
    );
    expect(await readFile(ovpnPath, "utf-8")).toBe(result.patchedOvpnContent);
    await expect(stat(authPath)).rejects.toThrow();
  });

  test("migrates missing auth file references into inline credentials when username is supplied", async () => {
    const fixture = openVpnAuthFixtures.missingAuthFile;
    const ovpnPath = await writeFixture(fixtureDir, fixture);

    const result = await patchOpenVpnAuthInPlace({
      ovpnPath,
      username: "vpn-user",
      password: AUTH_PASSWORD,
    });

    expect(result).toEqual(
      referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD, "vpn-user"),
    );
    expect(await readFile(ovpnPath, "utf-8")).toBe(result.patchedOvpnContent);
  });

  test("leaves unusable and duplicate auth file cases untouched", async () => {
    for (const fixture of [
      openVpnAuthFixtures.unusableAuthFile,
      openVpnAuthFixtures.duplicateAuthUserPass,
    ]) {
      const ovpnPath = await writeFixture(fixtureDir, fixture);
      const result = await patchOpenVpnAuthInPlace({
        ovpnPath,
        username: "vpn-user",
        password: AUTH_PASSWORD,
      });

      expect(result).toEqual(
        referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD, "vpn-user"),
      );
      expect(await readFile(ovpnPath, "utf-8")).toBe(fixture.ovpnContent);
    }
  });
});
