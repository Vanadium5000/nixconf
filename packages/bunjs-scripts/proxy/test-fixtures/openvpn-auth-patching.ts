/**
 * Fixtures keep the auth patching contract explicit before runtime wiring lands.
 */

export interface OpenVpnAuthFixture {
  name: string;
  ovpnFileName: string;
  ovpnContent: string;
  authFileName?: string;
  authFileContent?: string;
}

export const AUTH_PASSWORD = "vpn-password";

export const openVpnAuthFixtures = {
  bareAuthUserPass: {
    name: "bare auth-user-pass",
    ovpnFileName: "us_wyoming.ovpn",
    ovpnContent: `client
remote us-wyoming-pf.privacy.network 1198
auth-user-pass
verb 1
`,
  },
  referencedUsernameOnly: {
    name: "referenced auth file with username only",
    ovpnFileName: "uk_london.ovpn",
    ovpnContent: `client
remote uk-london.privacy.network 1198
auth-user-pass uk_london.auth
verb 1
`,
    authFileName: "uk_london.auth",
    authFileContent: `vpn-user\n`,
  },
  referencedUsernameAndPassword: {
    name: "referenced auth file with username and password",
    ovpnFileName: "AirVPN GB London Alathfar.ovpn",
    ovpnContent: `client
remote gb-london.airvpn.example 1194
auth-user-pass AirVPN GB London Alathfar.auth
verb 1
`,
    authFileName: "AirVPN GB London Alathfar.auth",
    authFileContent: `vpn-user\n${AUTH_PASSWORD}\n`,
  },
  missingAuthFile: {
    name: "missing auth file reference",
    ovpnFileName: "us_seattle.ovpn",
    ovpnContent: `client
remote us-seattle.privacy.network 1198
auth-user-pass us_seattle.auth
verb 1
`,
    authFileName: "us_seattle.auth",
  },
  unusableAuthFile: {
    name: "unusable auth file reference",
    ovpnFileName: "de_berlin.ovpn",
    ovpnContent: `client
remote de-berlin.privacy.network 1198
auth-user-pass de_berlin.auth
verb 1
`,
    authFileName: "de_berlin.auth",
    authFileContent: `vpn-user\n${AUTH_PASSWORD}\nextra-line\n`,
  },
  duplicateAuthUserPass: {
    name: "duplicate auth-user-pass directives",
    ovpnFileName: "ca_toronto.ovpn",
    ovpnContent: `client
remote ca-toronto.privacy.network 1198
auth-user-pass
auth-user-pass ca_toronto.auth
verb 1
`,
    authFileName: "ca_toronto.auth",
    authFileContent: `vpn-user\n`,
  },
} satisfies Record<string, OpenVpnAuthFixture>;
