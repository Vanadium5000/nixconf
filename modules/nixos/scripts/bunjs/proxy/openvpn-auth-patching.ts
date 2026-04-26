import { readFile, rename, rm, writeFile } from "fs/promises";
import { basename, dirname, join, resolve } from "path";

export type OpenVpnAuthPatchClassification =
  | "bare-auth-user-pass"
  | "inline-auth-user-pass"
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
  username: string | null;
}

interface InspectOpenVpnAuthOptions {
  ovpnFileName: string;
  ovpnContent: string;
  authFileContent?: string;
  username?: string;
  password: string;
}

interface PatchOpenVpnAuthInPlaceOptions {
  ovpnPath: string;
  username?: string;
  password: string;
}

const AUTH_DIRECTIVE =
  /^[ \t]*auth-user-pass(?:[ \t]+(?<path>[^\r\n]+))?[ \t]*$/gm;
const INLINE_AUTH_BLOCK =
  /\n?<auth-user-pass>\r?\n[\s\S]*?\r?\n<\/auth-user-pass>[ \t]*\r?\n?/gm;

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

function stripInlineAuthBlock(content: string): string {
  return content.replace(INLINE_AUTH_BLOCK, "\n");
}

function buildInlineAuthBlock(username: string, password: string): string {
  return `<auth-user-pass>\n${username}\n${password}\n</auth-user-pass>\n`;
}

function replaceDirectiveWithBareAuth(content: string): string {
  return content.replace(AUTH_DIRECTIVE, "auth-user-pass");
}

function appendInlineBlock(
  content: string,
  username: string,
  password: string,
): string {
  const normalized = ensureTrailingNewline(
    stripInlineAuthBlock(content).trimEnd(),
  );
  return `${normalized}${buildInlineAuthBlock(username, password)}`;
}

async function atomicWriteFile(path: string, content: string): Promise<void> {
  const tmpPath = join(dirname(path), `.${basename(path)}.tmp.${process.pid}`);
  await writeFile(tmpPath, content);
  await rename(tmpPath, path);
}

function resolveAuthPath(ovpnFileName: string, referencedPath: string): string {
  return referencedPath.startsWith("/")
    ? referencedPath
    : join(dirname(ovpnFileName), referencedPath);
}

export function inspectOpenVpnAuth(
  options: InspectOpenVpnAuthOptions,
): OpenVpnAuthPatchResult {
  const inlineBlockMatch = options.ovpnContent.match(INLINE_AUTH_BLOCK);
  if (inlineBlockMatch) {
    return {
      classification: "inline-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  const directives = [...options.ovpnContent.matchAll(AUTH_DIRECTIVE)];

  if (directives.length === 0) {
    return {
      classification: "missing-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  if (directives.length > 1) {
    return {
      classification: "duplicate-auth-user-pass",
      changed: false,
      authFileName: null,
      patchedOvpnContent: options.ovpnContent,
      patchedAuthFileContent: null,
      username: null,
    };
  }

  const directive = directives[0]!;
  const referencedPath = directive.groups?.path?.trim();

  if (!referencedPath) {
    const username = options.username?.trim() || null;
    if (!username) {
      return {
        classification: "bare-auth-user-pass",
        changed: false,
        authFileName: getSiblingAuthFileName(options.ovpnFileName),
        patchedOvpnContent: options.ovpnContent,
        patchedAuthFileContent: null,
        username: null,
      };
    }

    return {
      classification: "bare-auth-user-pass",
      changed: true,
      authFileName: getSiblingAuthFileName(options.ovpnFileName),
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(options.ovpnContent),
        username,
        options.password,
      ),
      patchedAuthFileContent: null,
      username,
    };
  }

  if (options.authFileContent === undefined) {
    const username = options.username?.trim() || null;
    if (!username) {
      return {
        classification: "missing-auth-file",
        changed: false,
        authFileName: referencedPath,
        patchedOvpnContent: options.ovpnContent,
        patchedAuthFileContent: null,
        username: null,
      };
    }

    return {
      classification: "missing-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(options.ovpnContent),
        username,
        options.password,
      ),
      patchedAuthFileContent: null,
      username,
    };
  }

  const authLines = getAuthLines(options.authFileContent);

  if (authLines.length === 1) {
    return {
      classification: "username-only-auth-file",
      changed: true,
      authFileName: referencedPath,
      patchedOvpnContent: appendInlineBlock(
        replaceDirectiveWithBareAuth(options.ovpnContent),
        authLines[0]!,
        options.password,
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
        replaceDirectiveWithBareAuth(options.ovpnContent),
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
    patchedOvpnContent: options.ovpnContent,
    patchedAuthFileContent: null,
    username: null,
  };
}

export async function patchOpenVpnAuthInPlace(
  options: PatchOpenVpnAuthInPlaceOptions,
): Promise<OpenVpnAuthPatchResult> {
  const ovpnContent = await readFile(options.ovpnPath, "utf-8");
  const directives = [...ovpnContent.matchAll(AUTH_DIRECTIVE)];
  const referencedPath =
    directives.length === 1 ? directives[0]?.groups?.path?.trim() : null;
  const authPath = referencedPath
    ? referencedPath.startsWith("/")
      ? referencedPath
      : resolve(dirname(options.ovpnPath), referencedPath)
    : join(
        dirname(options.ovpnPath),
        getSiblingAuthFileName(basename(options.ovpnPath)),
      );

  let authFileContent: string | undefined;
  try {
    authFileContent = await readFile(authPath, "utf-8");
  } catch {
    authFileContent = undefined;
  }

  const result = inspectOpenVpnAuth({
    ovpnFileName: options.ovpnPath,
    ovpnContent,
    authFileContent,
    username: options.username,
    password: options.password,
  });

  if (!result.changed) {
    return result;
  }

  if (result.patchedOvpnContent !== ovpnContent) {
    await atomicWriteFile(options.ovpnPath, result.patchedOvpnContent);
  }

  if (referencedPath) {
    try {
      await rm(authPath);
    } catch {
      // Ignore cleanup failures so an already-patched .ovpn still becomes usable.
    }
  }

  return result;
}
