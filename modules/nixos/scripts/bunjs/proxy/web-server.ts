#!/usr/bin/env bun
/**
 * VPN Proxy Web UI — ElysiaJS Backend
 *
 * REST API + SSE for the shadcn management dashboard. Routes are type-validated
 * and documented via OpenAPI (Swagger UI at /api/docs). Authenticated via a
 * single API key stored in password-store (VPN_PROXY_API_KEY env var).
 *
 * Architecture:
 *   Browser ──► ElysiaJS (:10802) ──► shared.ts/settings.ts/proxy-tester.ts
 *                  │
 *                  ├── GET  /api/status      → proxy state + transfer stats
 *                  ├── GET  /api/vpns        → all available VPNs
 *                  ├── GET  /api/settings    → current settings
 *                  ├── PUT  /api/settings    → update settings
 *                  ├── POST /api/test/:slug  → test single proxy
 *                  ├── POST /api/test-all    → mass test (SSE progress)
 *                  ├── GET  /api/test-results → test results
 *                  ├── GET  /api/export/:fmt → export proxy lists
 *                  ├── GET  /api/match/:pat  → pattern match VPNs
 *                  ├── GET  /api/sse/status  → real-time status SSE stream
 *                  └── Static files          → frontend SPA
 */

import { Elysia, t } from "elysia";
import { swagger } from "@elysiajs/swagger";

import { cors } from "@elysiajs/cors";
import {
  loadState,
  getStatus,
  stopAllProxies,
  forceRotateRandom,
  destroyNamespace,
  setNamespacePinned,
  CONFIG,
} from "./shared";
import {
  loadSettings,
  saveSettings,
  mergeSettings,
  getDefaultSettings,
  getDynamicIdleTimeout,
  type ProxySettings,
} from "./settings";
import { listVpns, resolveVpnByPattern, invalidateCache } from "./vpn-resolver";
import {
  applyAuthPatch,
  listAuthPatchCandidates,
  type AuthPatchCandidate,
  type AuthPatchKind,
  type AuthPatchOverview,
  type PatchAuthRequest,
} from "./auth-patching";
import {
  testSingleProxy,
  testAllProxies,
  loadTestResults,
  getFailedSlugs,
} from "./proxy-tester";

// ============================================================================
// Auth
// ============================================================================

const API_KEY = process.env.VPN_PROXY_API_KEY || "";

let currentTestController: AbortController | null = null;
let currentTestProgress: { completed: number; total: number } | null = null;
let currentTestSlug: string | null = null;

type AuthPatchGroupKey = keyof AuthPatchOverview;

interface AuthPatchCandidateRow extends AuthPatchCandidate {
  group: AuthPatchGroupKey;
  inputMode: "password-only" | "username-password" | "manual-review";
  requiresUsername: boolean;
  requiresPassword: boolean;
  canPatch: boolean;
  manualReview: boolean;
}

interface AuthPatchGroupResponse {
  key: AuthPatchGroupKey;
  kind: AuthPatchKind;
  title: string;
  description: string;
  count: number;
  requiresUsername: boolean;
  requiresPassword: boolean;
  canPatch: boolean;
  manualReview: boolean;
  items: AuthPatchCandidateRow[];
}

interface AuthPatchListResponse {
  summary: {
    totalCandidates: number;
    patchableCandidates: number;
    manualReviewCandidates: number;
    passwordOnlyCandidates: number;
    usernamePasswordCandidates: number;
    ambiguousCandidates: number;
  };
  groups: Record<AuthPatchGroupKey, AuthPatchGroupResponse>;
  rows: AuthPatchCandidateRow[];
}

interface AuthPatchSuccessResponse {
  ok: true;
  ovpnPath: string;
  slug: string;
  displayName: string;
  kind: "password-only" | "username-password";
  authFilePath: string;
  username: string;
}

interface AuthPatchErrorResponse {
  ok: false;
  ovpnPath: string;
  slug: string | null;
  displayName: string | null;
  kind: Exclude<AuthPatchKind, "none"> | null;
  code:
    | "not-candidate"
    | "manual-review-required"
    | "missing-username"
    | "missing-password"
    | "patch-failed";
  manualReview: boolean;
  message: string;
}

interface AuthPatchBulkResponse {
  totals: {
    requested: number;
    patched: number;
    failed: number;
  };
  results: Array<AuthPatchSuccessResponse | AuthPatchErrorResponse>;
}

if (!API_KEY) {
  console.error(
    "[web-server] WARNING: VPN_PROXY_API_KEY not set. API is unauthenticated!",
  );
}

function checkAuth(headers: Record<string, string | undefined>): boolean {
  if (!API_KEY) return true;
  const authHeader = headers["authorization"] || headers["x-api-key"];
  if (!authHeader) return false;
  // Support "Bearer <key>" or raw key
  const key = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7)
    : authHeader;
  return key === API_KEY;
}

function getAuthPatchRowGroup(
  kind: Exclude<AuthPatchKind, "none">,
): AuthPatchGroupKey {
  switch (kind) {
    case "password-only":
      return "passwordOnly";
    case "username-password":
      return "usernamePassword";
    case "ambiguous":
      return "ambiguous";
  }
}

function toAuthPatchCandidateRow(
  candidate: AuthPatchCandidate,
): AuthPatchCandidateRow {
  const group = getAuthPatchRowGroup(candidate.kind);

  return {
    ...candidate,
    group,
    inputMode:
      candidate.kind === "password-only"
        ? "password-only"
        : candidate.kind === "username-password"
          ? "username-password"
          : "manual-review",
    requiresUsername: candidate.kind === "username-password",
    requiresPassword: candidate.kind !== "ambiguous",
    canPatch: candidate.kind !== "ambiguous",
    manualReview: candidate.kind === "ambiguous",
  };
}

function buildAuthPatchListResponse(
  overview: AuthPatchOverview,
): AuthPatchListResponse {
  const passwordOnly = overview.passwordOnly.map(toAuthPatchCandidateRow);
  const usernamePassword = overview.usernamePassword.map(
    toAuthPatchCandidateRow,
  );
  const ambiguous = overview.ambiguous.map(toAuthPatchCandidateRow);
  const rows = [...passwordOnly, ...usernamePassword, ...ambiguous];

  return {
    summary: {
      totalCandidates: rows.length,
      patchableCandidates: passwordOnly.length + usernamePassword.length,
      manualReviewCandidates: ambiguous.length,
      passwordOnlyCandidates: passwordOnly.length,
      usernamePasswordCandidates: usernamePassword.length,
      ambiguousCandidates: ambiguous.length,
    },
    groups: {
      passwordOnly: {
        key: "passwordOnly",
        kind: "password-only",
        title: "Password-only",
        description:
          "Username already exists in the auth file, so only the missing password should be written.",
        count: passwordOnly.length,
        requiresUsername: false,
        requiresPassword: true,
        canPatch: true,
        manualReview: false,
        items: passwordOnly,
      },
      usernamePassword: {
        key: "usernamePassword",
        kind: "username-password",
        title: "Username + password",
        description:
          "The config has a bare auth-user-pass directive or a missing/unusable auth file, so both credentials are required.",
        count: usernamePassword.length,
        requiresUsername: true,
        requiresPassword: true,
        canPatch: true,
        manualReview: false,
        items: usernamePassword,
      },
      ambiguous: {
        key: "ambiguous",
        kind: "ambiguous",
        title: "Manual review required",
        description:
          "These configs need manual review before patching because the auth-user-pass layout is ambiguous or unusable.",
        count: ambiguous.length,
        requiresUsername: false,
        requiresPassword: false,
        canPatch: false,
        manualReview: true,
        items: ambiguous,
      },
    },
    rows,
  };
}

async function getAuthPatchCandidateIndex(): Promise<
  Map<string, AuthPatchCandidateRow>
> {
  const overview = await listAuthPatchCandidates();
  const response = buildAuthPatchListResponse(overview);
  return new Map(response.rows.map((row) => [row.ovpnPath, row]));
}

async function applyAuthPatchForRoute(
  request: PatchAuthRequest,
  candidateIndex: Map<string, AuthPatchCandidateRow>,
): Promise<AuthPatchSuccessResponse | AuthPatchErrorResponse> {
  const candidate = candidateIndex.get(request.ovpnPath);

  if (!candidate) {
    return {
      ok: false,
      ovpnPath: request.ovpnPath,
      slug: null,
      displayName: null,
      kind: null,
      code: "not-candidate",
      manualReview: false,
      message:
        "This OpenVPN config is not a pending auth patch candidate. Refresh the auth inspection data before retrying.",
    };
  }

  if (candidate.manualReview) {
    return {
      ok: false,
      ovpnPath: candidate.ovpnPath,
      slug: candidate.slug,
      displayName: candidate.displayName,
      kind: candidate.kind,
      code: "manual-review-required",
      manualReview: true,
      message: candidate.reason,
    };
  }

  if (!request.password.trim()) {
    return {
      ok: false,
      ovpnPath: candidate.ovpnPath,
      slug: candidate.slug,
      displayName: candidate.displayName,
      kind: candidate.kind,
      code: "missing-password",
      manualReview: false,
      message: "Password is required to patch OpenVPN auth files.",
    };
  }

  if (candidate.requiresUsername && !request.username?.trim()) {
    return {
      ok: false,
      ovpnPath: candidate.ovpnPath,
      slug: candidate.slug,
      displayName: candidate.displayName,
      kind: candidate.kind,
      code: "missing-username",
      manualReview: false,
      message:
        "Username is required when the config needs a full username/password auth file.",
    };
  }

  try {
    const result = await applyAuthPatch(request);
    if (candidate.kind === "password-only") {
      return {
        ok: true,
        ovpnPath: candidate.ovpnPath,
        slug: candidate.slug,
        displayName: candidate.displayName,
        kind: "password-only",
        authFilePath: result.authFilePath,
        username: result.username,
      };
    }

    return {
      ok: true,
      ovpnPath: candidate.ovpnPath,
      slug: candidate.slug,
      displayName: candidate.displayName,
      kind: "username-password",
      authFilePath: result.authFilePath,
      username: result.username,
    };
  } catch (error) {
    return {
      ok: false,
      ovpnPath: candidate.ovpnPath,
      slug: candidate.slug,
      displayName: candidate.displayName,
      kind: candidate.kind,
      code: "patch-failed",
      manualReview: false,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

// ============================================================================
// SSE Client Registry
// ============================================================================

const sseClients = new Set<ReadableStreamDefaultController<string>>();

async function broadcastStatus() {
  if (sseClients.size === 0) return;
  const state = await loadState();
  const settings = await loadSettings();
  const activeCount = Object.keys(state.namespaces).length;
  const data = JSON.stringify({
    ...state,
    activeCount,
    currentTimeoutSeconds: getDynamicIdleTimeout(
      activeCount,
      settings.idleTimeoutTiers,
    ),
    socks5Port: CONFIG.SOCKS5_PORT,
    httpPort: CONFIG.HTTP_PORT,
    timestamp: Date.now(),
  });
  const event = `data: ${data}\n\n`;
  for (const controller of sseClients) {
    try {
      controller.enqueue(event);
    } catch {
      sseClients.delete(controller);
    }
  }
}

// Broadcast status every 2 seconds to connected SSE clients
setInterval(broadcastStatus, 2000);

// ============================================================================
// App
// ============================================================================

const app = new Elysia()
  .use(cors())
  .use(
    swagger({
      documentation: {
        info: {
          title: "VPN Proxy Management API",
          version: "1.0.0",
          description:
            "API for managing VPN SOCKS5/HTTP proxy system with dynamic timeouts, pattern matching, and health testing.",
        },
        tags: [
          { name: "Status", description: "Proxy status and control" },
          { name: "VPNs", description: "VPN listing and pattern matching" },
          { name: "Auth", description: "OpenVPN auth patching" },
          { name: "Settings", description: "Persistent configuration" },
          { name: "Testing", description: "Proxy health testing" },
          { name: "Export", description: "Proxy list export" },
        ],
      },
      path: "/api/docs",
    }),
  )
  // Auth guard for all /api routes
  .onBeforeHandle(({ request, set }) => {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api/")) return;
    // Allow docs and SSE without auth check on the guard
    if (url.pathname.startsWith("/api/docs")) return;

    if (!checkAuth(Object.fromEntries(request.headers))) {
      set.status = 401;
      return {
        error: "Unauthorized. Provide API key via Authorization header.",
      };
    }
  })

  // ======================== Status ========================

  .get(
    "/api/status",
    async () => {
      const state = await loadState();
      const settings = await loadSettings();
      const activeCount = Object.keys(state.namespaces).length;
      return {
        namespaces: state.namespaces,
        random: state.random,
        nextIndex: state.nextIndex,
        activeCount,
        currentTimeoutSeconds: getDynamicIdleTimeout(
          activeCount,
          settings.idleTimeoutTiers,
        ),
        socks5Port: CONFIG.SOCKS5_PORT,
        httpPort: CONFIG.HTTP_PORT,
        timestamp: Date.now(),
      };
    },
    { detail: { tags: ["Status"] } },
  )

  .get(
    "/api/openapi-url",
    async ({ request }) => {
      const url = new URL(request.url);
      return {
        docsUrl: `${url.origin}/api/docs`,
        specUrl: `${url.origin}/api/docs/json`,
      };
    },
    { detail: { tags: ["Status"] } },
  )

  .get(
    "/api/status/text",
    async () => {
      return new Response(await getStatus(), {
        headers: { "Content-Type": "text/plain" },
      });
    },
    { detail: { tags: ["Status"] } },
  )

  .post(
    "/api/stop-all",
    async () => {
      await stopAllProxies();
      return { success: true };
    },
    { detail: { tags: ["Status"] } },
  )

  .post(
    "/api/rotate-random",
    async () => {
      const result = await forceRotateRandom();
      return { rotatedTo: result };
    },
    { detail: { tags: ["Status"] } },
  )

  .delete(
    "/api/proxy/:slug",
    async ({ params: { slug } }) => {
      const state = await loadState();
      if (!state.namespaces[slug]) {
        return { error: "Namespace not found" };
      }
      await destroyNamespace(slug, state);
      return { success: true };
    },
    {
      params: t.Object({ slug: t.String() }),
      detail: { tags: ["Status"] },
    },
  )

  .post(
    "/api/proxy/:slug/pin",
    async ({ params: { slug } }) => {
      await setNamespacePinned(slug, true);
      return { success: true };
    },
    {
      params: t.Object({ slug: t.String() }),
      detail: { tags: ["Status"] },
    },
  )

  .post(
    "/api/proxy/:slug/unpin",
    async ({ params: { slug } }) => {
      await setNamespacePinned(slug, false);
      return { success: true };
    },
    {
      params: t.Object({ slug: t.String() }),
      detail: { tags: ["Status"] },
    },
  )

  // ======================== SSE ========================

  .get(
    "/api/sse/status",
    ({ request }) => {
      if (!checkAuth(Object.fromEntries(request.headers))) {
        return new Response("Unauthorized", { status: 401 });
      }

      const stream = new ReadableStream<string>({
        start(controller) {
          sseClients.add(controller);
          // Send initial status immediately
          loadState().then(async (state) => {
            const settings = await loadSettings();
            const activeCount = Object.keys(state.namespaces).length;
            const data = JSON.stringify({
              ...state,
              activeCount,
              currentTimeoutSeconds: getDynamicIdleTimeout(
                activeCount,
                settings.idleTimeoutTiers,
              ),
              socks5Port: CONFIG.SOCKS5_PORT,
              httpPort: CONFIG.HTTP_PORT,
              timestamp: Date.now(),
            });
            try {
              controller.enqueue(`data: ${data}\n\n`);
            } catch {
              sseClients.delete(controller);
            }
          });
        },
        cancel(controller) {
          sseClients.delete(controller);
        },
      });

      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    },
    { detail: { tags: ["Status"] } },
  )

  // ======================== VPNs ========================

  .get(
    "/api/vpns",
    async () => {
      const vpns = await listVpns();
      const testResults = await loadTestResults();
      return vpns.map((v) => ({
        ...v,
        testResult: testResults.results[v.slug] ?? null,
      }));
    },
    { detail: { tags: ["VPNs"] } },
  )

  .post(
    "/api/vpns/refresh",
    async () => {
      invalidateCache();
      const vpns = await listVpns();
      return { count: vpns.length };
    },
    { detail: { tags: ["VPNs"] } },
  )

  .get(
    "/api/match/:pattern",
    async ({ params: { pattern } }) => {
      const matches = await resolveVpnByPattern(decodeURIComponent(pattern));
      return matches;
    },
    {
      params: t.Object({ pattern: t.String() }),
      detail: { tags: ["VPNs"] },
    },
  )

  .get(
    "/api/auth-patches",
    async () => {
      return buildAuthPatchListResponse(await listAuthPatchCandidates());
    },
    { detail: { tags: ["Auth"] } },
  )

  .get(
    "/api/auth-patches/candidates",
    async () => {
      return buildAuthPatchListResponse(await listAuthPatchCandidates());
    },
    { detail: { tags: ["Auth"] } },
  )

  .post(
    "/api/auth-patches/apply-one",
    async ({ body, set }) => {
      const result = await applyAuthPatchForRoute(
        body,
        await getAuthPatchCandidateIndex(),
      );

      if (!result.ok) {
        set.status = result.code === "manual-review-required" ? 409 : 400;
        return result;
      }

      invalidateCache();
      return result;
    },
    {
      body: t.Object({
        ovpnPath: t.String(),
        username: t.Optional(t.String()),
        password: t.String(),
      }),
      detail: { tags: ["Auth"] },
    },
  )

  .post(
    "/api/auth-patches/apply",
    async ({ body, set }) => {
      if (body.items.length === 0) {
        set.status = 400;
        return {
          totals: { requested: 0, patched: 0, failed: 0 },
          results: [],
          error: "At least one auth patch item is required.",
        };
      }

      const candidateIndex = await getAuthPatchCandidateIndex();
      const results: Array<AuthPatchSuccessResponse | AuthPatchErrorResponse> =
        [];

      for (const item of body.items) {
        results.push(
          await applyAuthPatchForRoute(
            {
              ovpnPath: item.ovpnPath,
              username: item.username,
              password: item.password,
            },
            candidateIndex,
          ),
        );
      }

      const patched = results.filter((result) => result.ok).length;
      const failed = results.length - patched;

      if (patched > 0) {
        invalidateCache();
      }

      const response: AuthPatchBulkResponse = {
        totals: {
          requested: results.length,
          patched,
          failed,
        },
        results,
      };

      if (patched === 0) {
        set.status = results.some(
          (result) => !result.ok && result.code === "manual-review-required",
        )
          ? 409
          : 400;
      }

      return response;
    },
    {
      body: t.Object({
        items: t.Array(
          t.Object({
            ovpnPath: t.String(),
            username: t.Optional(t.String()),
            password: t.String(),
          }),
        ),
      }),
      detail: { tags: ["Auth"] },
    },
  )

  .post(
    "/api/auth-patches/apply-bulk",
    async ({ body, set }) => {
      if (body.items.length === 0) {
        set.status = 400;
        return {
          totals: { requested: 0, patched: 0, failed: 0 },
          results: [],
          error: "At least one auth patch item is required.",
        };
      }

      const candidateIndex = await getAuthPatchCandidateIndex();
      const results: Array<AuthPatchSuccessResponse | AuthPatchErrorResponse> =
        [];

      for (const item of body.items) {
        results.push(
          await applyAuthPatchForRoute(
            {
              ovpnPath: item.ovpnPath,
              username: item.username,
              password: item.password,
            },
            candidateIndex,
          ),
        );
      }

      const patched = results.filter((result) => result.ok).length;
      const failed = results.length - patched;

      if (patched > 0) {
        invalidateCache();
      }

      const response: AuthPatchBulkResponse = {
        totals: {
          requested: results.length,
          patched,
          failed,
        },
        results,
      };

      if (patched === 0) {
        set.status = results.some(
          (result) => !result.ok && result.code === "manual-review-required",
        )
          ? 409
          : 400;
      }

      return response;
    },
    {
      body: t.Object({
        items: t.Array(
          t.Object({
            ovpnPath: t.String(),
            username: t.Optional(t.String()),
            password: t.String(),
          }),
        ),
      }),
      detail: { tags: ["Auth"] },
    },
  )

  // ======================== Settings ========================

  .get(
    "/api/settings",
    async () => {
      return await loadSettings();
    },
    { detail: { tags: ["Settings"] } },
  )

  .put(
    "/api/settings",
    async ({ body }) => {
      const updated = await mergeSettings(body as Partial<ProxySettings>);
      return updated;
    },
    {
      body: t.Partial(
        t.Object({
          idleTimeoutTiers: t.Array(
            t.Object({
              minActive: t.Number(),
              timeoutSeconds: t.Number(),
            }),
          ),
          patternParsing: t.Partial(
            t.Object({
              enabled: t.Boolean(),
              fieldPatterns: t.Array(
                t.Object({
                  name: t.String(),
                  regex: t.String(),
                  position: t.Number(),
                }),
              ),
              excludePatterns: t.Array(t.String()),
            }),
          ),
          testing: t.Partial(
            t.Object({
              enabled: t.Boolean(),
              intervalHours: t.Number(),
              testGapSeconds: t.Number(),
              excludeFailedFromRandom: t.Boolean(),
            }),
          ),
          webUi: t.Partial(
            t.Object({
              port: t.Number(),
            }),
          ),
        }),
      ),
      detail: { tags: ["Settings"] },
    },
  )

  .post(
    "/api/settings/reset",
    async () => {
      const defaults = getDefaultSettings();
      await saveSettings(defaults);
      return defaults;
    },
    { detail: { tags: ["Settings"] } },
  )

  // ======================== Testing ========================

  .get(
    "/api/test-results",
    async () => {
      return await loadTestResults();
    },
    { detail: { tags: ["Testing"] } },
  )
  .get(
    "/api/test-progress",
    async () => {
      return {
        running: !!currentTestController,
        progress: currentTestProgress,
        currentSlug: currentTestSlug,
      };
    },
    { detail: { tags: ["Testing"] } },
  )

  .post(
    "/api/test/:slug",
    async ({ params: { slug } }) => {
      const vpns = await listVpns();
      const vpn = vpns.find((v) => v.slug === slug);
      if (!vpn) {
        return { error: "VPN not found" };
      }
      const result = await testSingleProxy(vpn);
      return result;
    },
    {
      params: t.Object({ slug: t.String() }),
      detail: { tags: ["Testing"] },
    },
  )

  .get(
    "/api/test-all",
    async ({ request }) => {
      if (!checkAuth(Object.fromEntries(request.headers))) {
        return new Response("Unauthorized", { status: 401 });
      }

      // SSE stream for test progress
      const stream = new ReadableStream<string>({
        async start(controller) {
          const abortController = new AbortController();
          currentTestController = abortController;
          try {
            await testAllProxies((completed, total, result) => {
              currentTestProgress = { completed, total };
              currentTestSlug = result.slug;
              const event = JSON.stringify({ completed, total, result });
              try {
                controller.enqueue(`data: ${event}\n\n`);
              } catch {
                // Client disconnected
              }
            }, abortController.signal);
            controller.enqueue(`data: ${JSON.stringify({ done: true })}\n\n`);
            currentTestProgress = null;
            currentTestSlug = null;
            controller.close();
          } catch (error) {
            controller.enqueue(
              `data: ${JSON.stringify({ error: String(error) })}\n\n`,
            );
            currentTestProgress = null;
            currentTestSlug = null;
            controller.close();
          } finally {
            currentTestController = null;
          }
        },
      });

      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
        },
      });
    },
    { detail: { tags: ["Testing"] } },
  )

  .post(
    "/api/test-all/stop",
    async () => {
      if (currentTestController) {
        currentTestController.abort();
        currentTestController = null;
        currentTestProgress = null;
        currentTestSlug = null;
        return { stopped: true };
      }
      return { stopped: false };
    },
    { detail: { tags: ["Testing"] } },
  )

  .get(
    "/api/test-failed",
    async () => {
      const failed = await getFailedSlugs();
      return { slugs: [...failed] };
    },
    { detail: { tags: ["Testing"] } },
  )

  // ======================== Export ========================

  .get(
    "/api/export/:format",
    async ({ params: { format }, query }) => {
      const onlyWorking = query.working === "true";
      const slugs = query.slugs
        ? new Set(query.slugs.split(",").map((s) => s.trim()))
        : null;
      const vpns = await listVpns();
      const failedSlugs = onlyWorking ? await getFailedSlugs() : new Set();
      const filtered = vpns.filter((v) => {
        if (slugs && !slugs.has(v.slug)) return false;
        if (onlyWorking && failedSlugs.has(v.slug)) return false;
        return true;
      });

      let result: string;
      switch (format) {
        case "usernames":
          result = filtered.map((v) => v.slug).join(",");
          break;
        case "socks5":
          result = filtered
            .map((v) => `socks5h://${v.slug}@127.0.0.1:${CONFIG.SOCKS5_PORT}`)
            .join(",");
          break;
        case "http":
          result = filtered
            .map((v) => `http://${v.slug}:@127.0.0.1:${CONFIG.HTTP_PORT}`)
            .join(",");
          break;
        default:
          return { error: "Invalid format. Use: usernames, socks5, http" };
      }
      return new Response(result, {
        headers: { "Content-Type": "text/plain" },
      });
    },
    {
      params: t.Object({ format: t.String() }),
      query: t.Optional(
        t.Object({
          working: t.Optional(t.String()),
          slugs: t.Optional(t.String()),
        }),
      ),
      detail: { tags: ["Export"] },
    },
  );

// ============================================================================
// Static Files (frontend SPA)
// ============================================================================

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

const distDir =
  process.env.VPN_PROXY_WEB_DIST ||
  new URL("./web-ui/dist", import.meta.url).pathname;

// Build a lookup map of dist/ files at startup for O(1) static file resolution.
// Elysia's router silently drops routes added after chain compilation, so we
// bypass it entirely and intercept requests in Bun.serve's fetch handler.
const staticFiles = new Map<
  string,
  { filePath: string; contentType: string }
>();
try {
  const glob = new Bun.Glob("**/*");
  for (const relPath of glob.scanSync({ cwd: distDir, onlyFiles: true })) {
    if (relPath === "index.html") continue;
    const ext = relPath.substring(relPath.lastIndexOf("."));
    staticFiles.set(`/${relPath}`, {
      filePath: `${distDir}/${relPath}`,
      contentType: MIME_TYPES[ext] || "application/octet-stream",
    });
  }
} catch {
  // dist/ doesn't exist — API-only mode
}

function serveStatic(pathname: string): Response | null {
  const entry = staticFiles.get(pathname);
  if (entry) {
    return new Response(Bun.file(entry.filePath), {
      headers: { "Content-Type": entry.contentType },
    });
  }
  return null;
}

function serveIndex(): Response | null {
  const indexPath = `${distDir}/index.html`;
  const file = Bun.file(indexPath);
  // Bun.file is lazy — check size > 0 as a sync existence check
  if (file.size > 0) {
    return new Response(file, {
      headers: { "Content-Type": "text/html" },
    });
  }
  return null;
}

// ============================================================================
// Server Start
// ============================================================================

async function main() {
  const settings = await loadSettings();
  const port = settings.webUi.port;

  // Use Bun.serve directly so we can intercept static files before Elysia's
  // router. Elysia handles all /api/ routes; we handle static + SPA fallback.
  Bun.serve({
    port,
    async fetch(req) {
      const url = new URL(req.url);
      const pathname = url.pathname;

      if (pathname.startsWith("/api/")) {
        return app.fetch(req);
      }

      const staticResponse = serveStatic(pathname);
      if (staticResponse) return staticResponse;

      if (!pathname.match(/\.\w+$/) || pathname === "/") {
        const indexResponse = serveIndex();
        if (indexResponse) return indexResponse;
      }

      return app.fetch(req);
    },
  });

  console.log(
    `[web-server] VPN Proxy Web UI listening on http://0.0.0.0:${port}`,
  );
  console.log(`[web-server] API docs: http://localhost:${port}/api/docs`);
  if (!API_KEY) {
    console.log("[web-server] WARNING: No API key set. API is open!");
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(`[web-server] Fatal: ${error}`);
    process.exit(1);
  });
}

export { app };
