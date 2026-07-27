import type { OpenVpnAuthFixture } from "../test-fixtures/openvpn-auth-patching";

export type AuthPatchClassification =
  | "bare-auth-user-pass"
  | "inline-auth-user-pass"
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
  username: string | null;
}

const AUTH_DIRECTIVE =
  /^[ \t]*auth-user-pass(?:[ \t]+(?<path>[^\r\n]+))?[ \t]*$/gm;
const INLINE_AUTH_BLOCK =
  /\n?<auth-user-pass>\r?\n[\s\S]*?\r?\n<\/auth-user-pass>[ \t]*\r?\n?/gm;

function getAuthLines(content: string): string[] {
  return content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function stripInlineAuthBlock(content: string): string {
  return content.replace(INLINE_AUTH_BLOCK, "\n");
}

function replaceDirectiveWithBareAuth(content: string): string {
  return content.replace(AUTH_DIRECTIVE, "auth-user-pass");
}

function appendInlineBlock(
  content: string,
  username: string,
  password: string,
): string {
  const normalizedBase = `${stripInlineAuthBlock(content).trimEnd()}\n`;
  return `${normalizedBase}<auth-user-pass>\n${username}\n${password}\n</auth-user-pass>\n`;
}

export function referencePatchOpenVpnAuthFixture(
  fixture: OpenVpnAuthFixture,
  password: string,
  username = "vpn-user",
): AuthPatchResult {
  if (fixture.ovpnContent.match(INLINE_AUTH_BLOCK)) {
    return {
      classification: "inline-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  const directives = [...fixture.ovpnContent.matchAll(AUTH_DIRECTIVE)];

  if (directives.length === 0) {
    return {
      classification: "missing-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  if (directives.length > 1) {
    return {
      classification: "duplicate-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: fixture.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  const directive = directives[0]!;
  const referencedPath = directive.groups?.path?.trim();

  if (!referencedPath) {
    return {
      classification: "bare-auth-user-pass",
      changed: true,
      authFileName: `${fixture.ovpnFileName.replace(/\.ovpn$/, "")}.auth`,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(fixture.ovpnContent),
        username,
        password,
      ),
      patchedAuthFileContent: null,
      username,
    };
  }

  if (fixture.authFileContent === undefined) {
    return {
      classification: "missing-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(fixture.ovpnContent),
        username,
        password,
      ),
      patchedAuthFileContent: null,
      username,
    };
  }

  const authLines = getAuthLines(fixture.authFileContent);
  if (authLines.length === 1) {
    return {
      classification: "username-only-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(fixture.ovpnContent),
        authLines[0]!,
        password,
      ),
      patchedAuthFileContent: null,
      username: authLines[0]!,
    };
  }

  if (authLines.length === 2) {
    return {
      classification: "username-and-password-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(fixture.ovpnContent),
        authLines[0]!,
        authLines[1]!,
      ),
      patchedAuthFileContent: null,
      username: authLines[0]!,
    };
  }

  return {
    classification: "unusable-auth-file",
    changed: false,
    authFileName: referencedPath,
    patchedOvpnContent: fixture.ovpnContent,
    patchedAuthFileContent: null,
    username: null,
  };
}
