#!/usr/bin/env bun
/**
 * OpenVPN auth patching helpers.
 *
 * These helpers patch provider-managed `.ovpn` files in place so the same
 * configs keep working for the proxy and for any external OpenVPN consumer.
 */

import { readFile } from "fs/promises";
import { dirname, join } from "path";

import {
  inspectOpenVpnAuth,
  patchOpenVpnAuthInPlace,
  type OpenVpnAuthPatchClassification,
} from "./openvpn-auth-patching";
import { listVpns } from "./vpn-resolver";

export type AuthPatchKind =
  | "none"
  | "password-only"
  | "username-password"
  | "ambiguous";

export interface AuthPatchCandidate {
  slug: string;
  displayName: string;
  ovpnPath: string;
  kind: Exclude<AuthPatchKind, "none">;
  selectedByDefault: boolean;
  usernameHint: string | null;
  authFilePath: string | null;
  reason: string;
}

export interface AuthPatchOverview {
  passwordOnly: AuthPatchCandidate[];
  usernamePassword: AuthPatchCandidate[];
  ambiguous: AuthPatchCandidate[];
}

export interface PatchAuthRequest {
  ovpnPath: string;
  username?: string;
  password: string;
}

export interface PatchAuthResult {
  ovpnPath: string;
  authFilePath: string | null;
  username: string;
}

function getReason(classification: OpenVpnAuthPatchClassification): string {
  switch (classification) {
    case "missing-auth-user-pass":
      return "No auth-user-pass directive present.";
    case "duplicate-auth-user-pass":
      return "Multiple auth-user-pass directives require manual review.";
    case "missing-auth-file":
      return "Referenced auth file is missing, so credentials must be embedded inline.";
    case "unusable-auth-file":
      return "Referenced auth file layout requires manual review.";
    case "bare-auth-user-pass":
      return "Bare auth-user-pass needs inline embedded username and password.";
    case "username-only-auth-file":
      return "Referenced auth file already provides the username, so only the missing password is needed for inline embedding.";
    case "username-and-password-auth-file":
      return "Referenced auth file already contains both credentials and can be migrated inline.";
    case "inline-auth-user-pass":
      return "Credentials are already embedded inline in this .ovpn file.";
  }
}

function toCandidateKind(
  classification: OpenVpnAuthPatchClassification,
): Exclude<AuthPatchKind, "none"> | null {
  switch (classification) {
    case "username-only-auth-file":
      return "password-only";
    case "bare-auth-user-pass":
    case "missing-auth-file":
    case "username-and-password-auth-file":
      return "username-password";
    case "duplicate-auth-user-pass":
    case "unusable-auth-file":
      return "ambiguous";
    case "missing-auth-user-pass":
    case "inline-auth-user-pass":
      return null;
  }
}

async function readAuthFileIfPresent(
  authFilePath: string,
): Promise<string | undefined> {
  try {
    return await readFile(authFilePath, "utf-8");
  } catch {
    return undefined;
  }
}

async function inspectVpnCandidate(
  ovpnPath: string,
  displayName: string,
  slug: string,
): Promise<AuthPatchCandidate | null> {
  const ovpnContent = await readFile(ovpnPath, "utf-8");
  const siblingDir = dirname(ovpnPath);
  const bareResult = inspectOpenVpnAuth({
    ovpnFileName: ovpnPath.split("/").pop() ?? ovpnPath,
    ovpnContent,
    password: "__vpn_proxy_placeholder_password__",
  });

  const authFilePath = bareResult.authFileName
    ? join(siblingDir, bareResult.authFileName)
    : null;
  const authFileContent = authFilePath
    ? await readAuthFileIfPresent(authFilePath)
    : undefined;

  const result = inspectOpenVpnAuth({
    ovpnFileName: ovpnPath.split("/").pop() ?? ovpnPath,
    ovpnContent,
    authFileContent,
    username: "__vpn_proxy_placeholder_username__",
    password: "__vpn_proxy_placeholder_password__",
  });

  const kind = toCandidateKind(result.classification);
  if (!kind) {
    return null;
  }

  const usernameHint =
    result.classification === "username-only-auth-file" && authFileContent
      ? (authFileContent
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean)[0] ?? null)
      : null;

  return {
    slug,
    displayName,
    ovpnPath,
    kind,
    selectedByDefault:
      result.classification === "bare-auth-user-pass" ||
      result.classification === "username-only-auth-file",
    usernameHint,
    authFilePath: result.authFileName
      ? join(siblingDir, result.authFileName)
      : null,
    reason: getReason(result.classification),
  };
}

export async function listAuthPatchCandidates(): Promise<AuthPatchOverview> {
  const vpns = await listVpns();
  const passwordOnly: AuthPatchCandidate[] = [];
  const usernamePassword: AuthPatchCandidate[] = [];
  const ambiguous: AuthPatchCandidate[] = [];

  for (const vpn of vpns) {
    const candidate = await inspectVpnCandidate(
      vpn.ovpnPath,
      vpn.displayName,
      vpn.slug,
    );
    if (!candidate) {
      continue;
    }

    if (candidate.kind === "password-only") {
      passwordOnly.push(candidate);
    } else if (candidate.kind === "username-password") {
      usernamePassword.push(candidate);
    } else {
      ambiguous.push(candidate);
    }
  }

  return { passwordOnly, usernamePassword, ambiguous };
}

export async function applyAuthPatch(
  request: PatchAuthRequest,
): Promise<PatchAuthResult> {
  const password = request.password.trim();
  if (!password) {
    throw new Error("Password is required to patch OpenVPN auth files.");
  }

  const result = await patchOpenVpnAuthInPlace({
    ovpnPath: request.ovpnPath,
    username: request.username?.trim(),
    password,
  });

  if (
    result.classification === "duplicate-auth-user-pass" ||
    result.classification === "unusable-auth-file" ||
    result.classification === "missing-auth-user-pass" ||
    result.classification === "inline-auth-user-pass"
  ) {
    throw new Error(getReason(result.classification));
  }

  const username = result.username ?? request.username?.trim() ?? "";
  if (!username) {
    throw new Error("Username is required to embed credentials inline.");
  }

  return {
    ovpnPath: request.ovpnPath,
    authFilePath: result.authFileName
      ? join(dirname(request.ovpnPath), result.authFileName)
      : null,
    username,
  };
}
