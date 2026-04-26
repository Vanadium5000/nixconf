import { readFile, rename, writeFile } from "fs/promises";
import { basename, dirname, join } from "path";

export type OpenVpnAuthPatchClassification =
  | "bare-auth-user-pass"
  | "password-only-auth-file"
  | "username-only-auth-file"
  | "username-and-password-auth-file"
  | "missing-auth-file"
  | "unusable-auth-file"
  | "duplicate-auth-user-pass"
  | "missing-auth-user-pass";

export interface OpenVpnAuthPatchResult {
  classification: OpenVpnAuthPatchClassification;
  changed: boolean;
  authFileName: string | null;
  patchedOvpnContent: string;
  patchedAuthFileContent: string | null;
}

interface InspectOpenVpnAuthOptions {
  ovpnFileName: string;
  ovpnContent: string;
  authFileContent?: string;
  password: string;
}

interface PatchOpenVpnAuthInPlaceOptions {
  ovpnPath: string;
  password: string;
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

function ensureTrailingNewline(content: string): string {
  return content.endsWith("\n") ? content : `${content}\n`;
}

async function atomicWriteFile(path: string, content: string): Promise<void> {
  const tmpPath = join(dirname(path), `.${basename(path)}.tmp.${process.pid}`);
  await writeFile(tmpPath, content);
  // Rename keeps the final swap atomic on the same filesystem.
  await rename(tmpPath, path);
}

export function inspectOpenVpnAuth(
  options: InspectOpenVpnAuthOptions,
): OpenVpnAuthPatchResult {
  const directives = [...options.ovpnContent.matchAll(AUTH_DIRECTIVE)];

  if (directives.length === 0) {
    return {
      classification: "missing-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  if (directives.length > 1) {
    return {
      classification: "duplicate-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  const directive = directives[0]!;
  const referencedPath = directive.groups?.path?.trim();

  if (!referencedPath) {
    const authFileName = getSiblingAuthFileName(options.ovpnFileName);
    return {
      classification: "bare-auth-user-pass",
      changed: true,
      authFileName,
      patchedOvpnContent: options.ovpnContent.replace(
        /^\s*auth-user-pass\s*$/m,
        `auth-user-pass ${authFileName}`,
      ),
      patchedAuthFileContent: `${options.password}\n`,
    };
  }

  if (options.authFileContent === undefined) {
    return {
      classification: "missing-auth-file",
      changed: false,
      authFileName: referencedPath,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
    };
  }

  const authLines = getAuthLines(options.authFileContent);

  if (authLines.length === 1) {
    if (authLines[0] === options.password) {
      return {
        classification: "password-only-auth-file",
        changed: false,
        authFileName: referencedPath,
        patchedOvpnContent: options.ovpnContent,
        patchedAuthFileContent: ensureTrailingNewline(options.authFileContent),
      };
    }

    return {
      classification: "username-only-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: `${authLines[0]}\n${options.password}\n`,
    };
  }

  if (authLines.length === 2) {
    return {
      classification: "username-and-password-auth-file",
      changed: false,
      authFileName: referencedPath,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: ensureTrailingNewline(options.authFileContent),
    };
  }

  return {
    classification: "unusable-auth-file",
    changed: false,
    authFileName: referencedPath,
    patchedOvpnContent: options.ovpnContent,
    patchedAuthFileContent: null,
  };
}

export async function patchOpenVpnAuthInPlace(
  options: PatchOpenVpnAuthInPlaceOptions,
): Promise<OpenVpnAuthPatchResult> {
  const ovpnContent = await readFile(options.ovpnPath, "utf-8");
  const directives = [...ovpnContent.matchAll(AUTH_DIRECTIVE)];
  const referencedPath =
    directives.length === 1 ? directives[0]?.groups?.path?.trim() : null;
  const authFileName =
    referencedPath || getSiblingAuthFileName(basename(options.ovpnPath));
  const authPath = join(dirname(options.ovpnPath), authFileName);

  let authFileContent: string | undefined;
  try {
    authFileContent = await readFile(authPath, "utf-8");
  } catch {
    authFileContent = undefined;
  }

  const result = inspectOpenVpnAuth({
    ovpnFileName: basename(options.ovpnPath),
    ovpnContent,
    authFileContent,
    password: options.password,
  });

  if (!result.changed) {
    return result;
  }

  if (result.patchedOvpnContent !== ovpnContent) {
    await atomicWriteFile(options.ovpnPath, result.patchedOvpnContent);
  }

  if (result.authFileName && result.patchedAuthFileContent !== null) {
    const targetAuthPath = join(dirname(options.ovpnPath), result.authFileName);
    const currentAuthContent = authFileContent;

    if (currentAuthContent !== result.patchedAuthFileContent) {
      // Patch the provider-managed auth file in place so OpenVPN reads one stable path.
      await atomicWriteFile(targetAuthPath, result.patchedAuthFileContent);
    }
  }

  return result;
}
