import { describe, expect, test } from "bun:test";

import {
  AUTH_PASSWORD,
  openVpnAuthFixtures,
  type OpenVpnAuthFixture,
} from "./test-fixtures/openvpn-auth-patching";
import { referencePatchOpenVpnAuthFixture } from "./test-support/openvpn-auth-patching-reference";

function rerunFixture(
  originalFixture: OpenVpnAuthFixture,
  password: string,
): ReturnType<typeof referencePatchOpenVpnAuthFixture> {
  const firstPass = referencePatchOpenVpnAuthFixture(originalFixture, password);

  return referencePatchOpenVpnAuthFixture(
    {
      ...originalFixture,
      ovpnContent: firstPass.patchedOvpnContent,
      authFileName: firstPass.authFileName ?? originalFixture.authFileName,
      authFileContent:
        firstPass.patchedAuthFileContent ?? originalFixture.authFileContent,
    },
    password,
  );
}

describe("OpenVPN auth patching contract", () => {
  test("classifies bare auth-user-pass as password-only patch work", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.bareAuthUserPass,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "bare-auth-user-pass",
      changed: true,
      authFileName: "us_wyoming.auth",
      patchedOvpnContent: `client
remote us-wyoming-pf.privacy.network 1198
auth-user-pass us_wyoming.auth
verb 1
`,
      patchedAuthFileContent: `${AUTH_PASSWORD}\n`,
    });
  });

  test("classifies username-only auth files as append-password work", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.referencedUsernameOnly,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "username-only-auth-file",
      changed: true,
      authFileName: "uk_london.auth",
      patchedOvpnContent:
        openVpnAuthFixtures.referencedUsernameOnly.ovpnContent,
      patchedAuthFileContent: `vpn-user\n${AUTH_PASSWORD}\n`,
    });
  });

  test("keeps username-plus-password auth files as already complete", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.referencedUsernameAndPassword,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "username-and-password-auth-file",
      changed: false,
      authFileName: "AirVPN GB London Alathfar.auth",
      patchedOvpnContent:
        openVpnAuthFixtures.referencedUsernameAndPassword.ovpnContent,
      patchedAuthFileContent: `vpn-user\n${AUTH_PASSWORD}\n`,
    });
  });

  test("treats missing auth files as unusable until implementation decides recovery", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.missingAuthFile,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "missing-auth-file",
      changed: false,
      authFileName: "us_seattle.auth",
      patchedOvpnContent: openVpnAuthFixtures.missingAuthFile.ovpnContent,
      patchedAuthFileContent: null,
    });
  });

  test("treats malformed multi-line auth files as unusable", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.unusableAuthFile,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "unusable-auth-file",
      changed: false,
      authFileName: "de_berlin.auth",
      patchedOvpnContent: openVpnAuthFixtures.unusableAuthFile.ovpnContent,
      patchedAuthFileContent: null,
    });
  });

  test("defines duplicate auth-user-pass as a no-patch safety stop", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.duplicateAuthUserPass,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "duplicate-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: openVpnAuthFixtures.duplicateAuthUserPass.ovpnContent,
      patchedAuthFileContent: null,
    });
  });

  test("stays idempotent on a second run after patching bare auth-user-pass", () => {
    const secondPass = rerunFixture(
      openVpnAuthFixtures.bareAuthUserPass,
      AUTH_PASSWORD,
    );

    expect(secondPass).toEqual({
      classification: "password-only-auth-file",
      changed: false,
      authFileName: "us_wyoming.auth",
      patchedOvpnContent: `client
remote us-wyoming-pf.privacy.network 1198
auth-user-pass us_wyoming.auth
verb 1
`,
      patchedAuthFileContent: `${AUTH_PASSWORD}\n`,
    });
  });

  test("stays idempotent on a second run after username-plus-password is already complete", () => {
    const secondPass = rerunFixture(
      openVpnAuthFixtures.referencedUsernameAndPassword,
      AUTH_PASSWORD,
    );

    expect(secondPass).toEqual({
      classification: "username-and-password-auth-file",
      changed: false,
      authFileName: "AirVPN GB London Alathfar.auth",
      patchedOvpnContent:
        openVpnAuthFixtures.referencedUsernameAndPassword.ovpnContent,
      patchedAuthFileContent: `vpn-user\n${AUTH_PASSWORD}\n`,
    });
  });
});
