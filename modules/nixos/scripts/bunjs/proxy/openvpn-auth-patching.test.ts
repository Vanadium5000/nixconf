import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "fs/promises";
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
          password: AUTH_PASSWORD,
        }),
      ).toEqual(referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD));
    }
  });

  test("patches bare auth-user-pass in place and stays idempotent on rerun", async () => {
    const ovpnPath = await writeFixture(
      fixtureDir,
      openVpnAuthFixtures.bareAuthUserPass,
    );

    const firstPass = await patchOpenVpnAuthInPlace({
      ovpnPath,
      password: AUTH_PASSWORD,
    });

    expect(firstPass).toEqual(
      referencePatchOpenVpnAuthFixture(
        openVpnAuthFixtures.bareAuthUserPass,
        AUTH_PASSWORD,
      ),
    );
    expect(await readFile(ovpnPath, "utf-8")).toBe(
      firstPass.patchedOvpnContent,
    );
    expect(await readFile(join(fixtureDir, "us_wyoming.auth"), "utf-8")).toBe(
      `${AUTH_PASSWORD}\n`,
    );

    const secondPass = await patchOpenVpnAuthInPlace({
      ovpnPath,
      password: AUTH_PASSWORD,
    });

    expect(secondPass).toEqual({
      classification: "password-only-auth-file",
      changed: false,
      authFileName: "us_wyoming.auth",
      patchedOvpnContent: firstPass.patchedOvpnContent,
      patchedAuthFileContent: `${AUTH_PASSWORD}\n`,
    });
  });

  test("appends the password without touching unrelated ovpn content", async () => {
    const fixture = openVpnAuthFixtures.referencedUsernameOnly;
    const ovpnPath = await writeFixture(fixtureDir, fixture);
    const beforeOvpn = await readFile(ovpnPath, "utf-8");

    const result = await patchOpenVpnAuthInPlace({
      ovpnPath,
      password: AUTH_PASSWORD,
    });

    expect(result).toEqual(
      referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD),
    );
    expect(await readFile(ovpnPath, "utf-8")).toBe(beforeOvpn);
    expect(
      await readFile(join(fixtureDir, fixture.authFileName!), "utf-8"),
    ).toBe(`vpn-user\n${AUTH_PASSWORD}\n`);
  });

  test("leaves unusable and missing auth file cases untouched", async () => {
    for (const fixture of [
      openVpnAuthFixtures.missingAuthFile,
      openVpnAuthFixtures.unusableAuthFile,
      openVpnAuthFixtures.duplicateAuthUserPass,
    ]) {
      const ovpnPath = await writeFixture(fixtureDir, fixture);
      const result = await patchOpenVpnAuthInPlace({
        ovpnPath,
        password: AUTH_PASSWORD,
      });

      expect(result).toEqual(
        referencePatchOpenVpnAuthFixture(fixture, AUTH_PASSWORD),
      );
      expect(await readFile(ovpnPath, "utf-8")).toBe(fixture.ovpnContent);
    }
  });
});
