import { basename } from "path";

import type { OpenVpnAuthFixture } from "../test-fixtures/openvpn-auth-patching";

export type AuthPatchClassification =
  | "bare-auth-user-pass"
  | "password-only-auth-file"
  | "username-only-auth-file"
  | "username-and-password-auth-file"
  | "missing-auth-file"
  | "unusable-auth-file"
  | "duplicate-auth-user-pass"
  | "missing-auth-user-pass";

export interface AuthPatchResult {
  classification: AuthPatchClassification;
  changed: boolean;
  authFileName: string | null;
  patchedOvpnContent: string;
  patchedAuthFileContent: string | null;
}

const AUTH_DIRECTIVE =
  /^[ \t]*auth-user-pass(?:[ \t]+(?<path>[^\r\n]+))?[ \t]*$/gm;

function getSiblingAuthFileName(ovpnFileName: string): string {
  return `${basename(ovpnFileName, ".ovpn")}.auth`;
}

function getAuthLines(content: string): string[] {
  return content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

export function referencePatchOpenVpnAuthFixture(
  fixture: OpenVpnAuthFixture,
  password: string,
): AuthPatchResult {
  const directives = [...fixture.ovpnContent.matchAll(AUTH_DIRECTIVE)];

  if (directives.length === 0) {
    return {
      classification: "missing-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  if (directives.length > 1) {
    return {
      classification: "duplicate-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  const directive = directives[0]!;
  const referencedPath = directive.groups?.path?.trim();

  if (!referencedPath) {
    const authFileName = getSiblingAuthFileName(fixture.ovpnFileName);
    return {
      classification: "bare-auth-user-pass",
      changed: true,
      authFileName,
      patchedOvpnContent: fixture.ovpnContent.replace(
        /^\s*auth-user-pass\s*$/m,
        `auth-user-pass ${authFileName}`,
      ),
      patchedAuthFileContent: `${password}\n`,
    };
  }

  if (fixture.authFileContent === undefined) {
    return {
      classification: "missing-auth-file",
      changed: false,
      authFileName: referencedPath,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  const authLines = getAuthLines(fixture.authFileContent);

  if (authLines.length === 1) {
    if (authLines[0] === password) {
      return {
        classification: "password-only-auth-file",
        changed: false,
        authFileName: referencedPath,
        patchedOvpnContent: fixture.ovpnContent,
        patchedAuthFileContent: fixture.authFileContent.endsWith("\n")
          ? fixture.authFileContent
          : `${fixture.authFileContent}\n`,
      };
    }

    return {
      classification: "username-only-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: `${authLines[0]}\n${password}\n`,
    };
  }

  if (authLines.length === 2) {
    return {
      classification: "username-and-password-auth-file",
      changed: false,
      authFileName: referencedPath,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: fixture.authFileContent.endsWith("\n")
        ? fixture.authFileContent
        : `${fixture.authFileContent}\n`,
    };
  }

  return {
    classification: "unusable-auth-file",
    changed: false,
    authFileName: referencedPath,
    patchedOvpnContent: fixture.ovpnContent,
    patchedAuthFileContent: null,
  };
}
