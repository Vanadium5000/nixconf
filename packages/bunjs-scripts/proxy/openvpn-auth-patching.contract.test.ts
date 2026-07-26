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
      authFileName: undefined,
      authFileContent: undefined,
    },
    password,
    firstPass.username ?? undefined,
  );
}

describe("OpenVPN auth patching contract", () => {
  test("patches bare auth-user-pass into inline embedded credentials", () => {
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
auth-user-pass
verb 1
<auth-user-pass>
vpn-user
${AUTH_PASSWORD}
</auth-user-pass>
`,
      patchedAuthFileContent: null,
      username: "vpn-user",
    });
  });

  test("migrates username-only auth files into inline embedded credentials", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.referencedUsernameOnly,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "username-only-auth-file",
      changed: true,
      authFileName: "uk_london.auth",
      patchedOvpnContent: `client
remote uk-london.privacy.network 1198
auth-user-pass
verb 1
<auth-user-pass>
vpn-user
${AUTH_PASSWORD}
</auth-user-pass>
`,
      patchedAuthFileContent: null,
      username: "vpn-user",
    });
  });

  test("migrates complete auth files into inline embedded credentials", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.referencedUsernameAndPassword,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "username-and-password-auth-file",
      changed: true,
      authFileName: "AirVPN GB London Alathfar.auth",
      patchedOvpnContent: `client
remote gb-london.airvpn.example 1194
auth-user-pass
verb 1
<auth-user-pass>
vpn-user
${AUTH_PASSWORD}
</auth-user-pass>
`,
      patchedAuthFileContent: null,
      username: "vpn-user",
    });
  });

  test("migrates missing auth file references using supplied credentials", () => {
    const result = referencePatchOpenVpnAuthFixture(
      openVpnAuthFixtures.missingAuthFile,
      AUTH_PASSWORD,
    );

    expect(result).toEqual({
      classification: "missing-auth-file",
      changed: true,
      authFileName: "us_seattle.auth",
      patchedOvpnContent: `client
remote us-seattle.privacy.network 1198
auth-user-pass
verb 1
<auth-user-pass>
vpn-user
${AUTH_PASSWORD}
</auth-user-pass>
`,
      patchedAuthFileContent: null,
      username: "vpn-user",
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
      username: null,
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
      username: null,
    });
  });

  test("stays idempotent after inline credentials are embedded", () => {
    const secondPass = rerunFixture(
      openVpnAuthFixtures.bareAuthUserPass,
      AUTH_PASSWORD,
    );

    expect(secondPass).toEqual({
      classification: "inline-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: `client
remote us-wyoming-pf.privacy.network 1198
auth-user-pass
verb 1
<auth-user-pass>
vpn-user
${AUTH_PASSWORD}
</auth-user-pass>
`,
      patchedAuthFileContent: null,
      username: null,
    });
  });
});
