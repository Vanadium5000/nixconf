// @ts-nocheck — Browser-only TSX; tsconfig targets node, not DOM.
import React, { useState, useEffect, useCallback, useRef } from "react";
import { createRoot } from "react-dom/client";
import {
  Moon,
  Sun,
  LogOut,
  RotateCcw,
  ShieldAlert,
  RefreshCw,
  Copy,
  CheckCircle2,
  XCircle,
  Square,
  Plus,
  Trash2,
} from "lucide-react";

// Bun.build handles this correctly regardless of TS errors.

import "./globals.css";
import { cn } from "./lib/utils";
import { Button } from "./components/ui/button";
import { Card, CardHeader, CardTitle, CardContent } from "./components/ui/card";
import {
  Table,
  TableHeader,
  TableRow,
  TableHead,
  TableBody,
  TableCell,
} from "./components/ui/table";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "./components/ui/tabs";
import { Input } from "./components/ui/input";
import { Switch } from "./components/ui/switch";
import { Badge } from "./components/ui/badge";
import { Progress } from "./components/ui/progress";
import { Label } from "./components/ui/label";

// ============================================================================
// API Client
// ============================================================================

let API_KEY = localStorage.getItem("vpn-proxy-api-key") || "";

function api(path: string, opts: RequestInit = {}) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {}),
    ...((opts.headers as Record<string, string>) || {}),
  };
  return fetch(`/api${path}`, { ...opts, headers });
}

// ============================================================================
// Types
// ============================================================================

interface NamespaceInfo {
  nsName: string;
  nsIndex: number;
  nsIp: string;
  socksPort: number;
  slug: string;
  vpnDisplayName: string;
  lastUsed: number;
  status: string;
  bytesIn: number;
  bytesOut: number;
  connections: number;
  pinned?: boolean;
}

interface ProxyStatus {
  namespaces: Record<string, NamespaceInfo>;
  random: { currentSlug: string; expiresAt: number } | null;
  activeCount: number;
  currentTimeoutSeconds: number;
  socks5Port: number;
  httpPort: number;
  timestamp: number;
}

interface VpnInfo {
  slug: string;
  displayName: string;
  countryCode: string;
  flag: string;
  testResult: {
    success: boolean;
    ip?: string;
    latencyMs?: number;
    error?: string;
    testedAt: number;
  } | null;
}

interface Settings {
  idleTimeoutTiers: { minActive: number; timeoutSeconds: number }[];
  patternParsing: {
    enabled: boolean;
    fieldPatterns: { name: string; regex: string; position: number }[];
    excludePatterns: string[];
  };
  testing: {
    enabled: boolean;
    intervalHours: number;
    testGapSeconds: number;
    excludeFailedFromRandom: boolean;
    lastFullTestAt: number | null;
    nextFullTestAt?: number | null;
  };
  webUi: { port: number };
}

interface AuthPatchCandidate {
  slug: string;
  displayName: string;
  ovpnPath: string;
  kind: "password-only" | "username-password" | "ambiguous";
  selectedByDefault: boolean;
  usernameHint: string | null;
  authFilePath: string | null;
  reason: string;
  // Additional fields from API response
  group: "passwordOnly" | "usernamePassword" | "ambiguous";
  inputMode: "password-only" | "username-password" | "manual-review";
  requiresUsername: boolean;
  requiresPassword: boolean;
  canPatch: boolean;
  manualReview: boolean;
}

interface AuthPatchOverview {
  passwordOnly: AuthPatchCandidate[];
  usernamePassword: AuthPatchCandidate[];
  ambiguous: AuthPatchCandidate[];
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
  groups: Record<
    "passwordOnly" | "usernamePassword" | "ambiguous",
    {
      key: "passwordOnly" | "usernamePassword" | "ambiguous";
      kind: "password-only" | "username-password" | "ambiguous";
      title: string;
      description: string;
      count: number;
      requiresUsername: boolean;
      requiresPassword: boolean;
      canPatch: boolean;
      manualReview: boolean;
      items: AuthPatchCandidate[];
    }
  >;
  rows: AuthPatchCandidate[];
}

interface TestResults {
  results: Record<
    string,
    { success: boolean; testedAt: number; [key: string]: any }
  >;
  lastFullTestAt: number | null;
  nextFullTestAt: number | null;
}

interface TestProgress {
  running: boolean;
  progress: { completed: number; total: number } | null;
  currentSlug: string | null;
}

type ToastMessage = { id: number; message: string };

function emitToast(message: string) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent("vpn-proxy-toast", { detail: message }));
}

function ToastHost() {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  useEffect(() => {
    const handler = (event: Event) => {
      const detail = (event as CustomEvent<string>).detail;
      const toast: ToastMessage = { id: Date.now(), message: detail };
      setToasts((prev) => [...prev, toast]);
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== toast.id));
      }, 2200);
    };
    window.addEventListener("vpn-proxy-toast", handler);
    return () => window.removeEventListener("vpn-proxy-toast", handler);
  }, []);

  return (
    <div className="fixed right-4 top-4 z-50 flex flex-col gap-2">
      {toasts.map((toast) => (
        <div
          key={toast.id}
          className="glass-panel px-3 py-2 text-xs uppercase tracking-wide text-accent"
        >
          {toast.message}
        </div>
      ))}
    </div>
  );
}

// ============================================================================
// Utility
// ============================================================================

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

function formatIdle(lastUsed: number): string {
  const secs = Math.floor((Date.now() - lastUsed) / 1000);
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}m ${s}s`;
}

function formatAgo(ts: number): string {
  const secs = Math.floor((Date.now() - ts) / 1000);
  if (secs < 60) return `${secs}s ago`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
  return `${Math.floor(secs / 86400)}d ago`;
}

// ============================================================================
// Auth Screen
// ============================================================================

function AuthScreen({ onAuth }: { onAuth: (key: string) => void }) {
  const [key, setKey] = useState("");
  return (
    <div className="flex flex-col items-center justify-center min-h-[80vh] gap-6 animate-in fade-in zoom-in duration-300">
      <div className="space-y-2 text-center">
        <h1 className="text-3xl font-bold tracking-tight text-primary">
          VPN Proxy Manager
        </h1>
        <p className="text-muted-foreground">Enter your API key to continue</p>
      </div>
      <div className="flex flex-col w-full max-w-[300px] gap-4">
        <Input
          type="password"
          placeholder="API Key"
          value={key}
          onChange={(e) => setKey(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && key && onAuth(key)}
          className="text-center"
        />
        <Button
          variant="default"
          onClick={() => key && onAuth(key)}
          className="w-full"
        >
          Authenticate
        </Button>
      </div>
    </div>
  );
}

// ============================================================================
// Dashboard Tab
// ============================================================================

function DashboardTab({ status }: { status: ProxyStatus | null }) {
  if (!status)
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Connecting...
      </div>
    );

  const namespaces = Object.values(status.namespaces);

  const handleStopAll = async () => {
    await api("/stop-all", { method: "POST" });
  };

  const handleRotate = async () => {
    await api("/rotate-random", { method: "POST" });
  };

  const handleDestroy = async (slug: string) => {
    await api(`/proxy/${slug}`, { method: "DELETE" });
  };

  const handlePin = async (slug: string, pinned?: boolean) => {
    await api(`/proxy/${slug}/${pinned ? "unpin" : "pin"}`, { method: "POST" });
    emitToast(pinned ? "Unpinned" : "Pinned");
  };

  const handleCopy = async (value: string) => {
    await navigator.clipboard.writeText(value);
    emitToast("Copied to clipboard");
  };

  return (
    <div className="space-y-6">
      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            Overview
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="flex flex-col items-center justify-center p-4 glass-soft rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.activeCount}
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                Active Proxies
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 glass-soft rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.currentTimeoutSeconds}s
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                Idle Timeout
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 glass-soft rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.socks5Port}
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                SOCKS5 Port
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 glass-soft rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.httpPort}
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                HTTP Port
              </div>
            </div>
          </div>
          <div className="mt-6 flex flex-wrap gap-3">
            <Button
              variant="outline"
              size="sm"
              onClick={handleRotate}
              className="gap-2"
            >
              <RotateCcw className="w-3.5 h-3.5" /> Rotate Random
            </Button>
            <Button
              variant="destructive"
              size="sm"
              onClick={handleStopAll}
              className="gap-2"
            >
              <ShieldAlert className="w-3.5 h-3.5" /> Stop All
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Active Proxies</CardTitle>
        </CardHeader>
        <CardContent>
          {namespaces.length === 0 ? (
            <p className="text-center py-8 text-muted-foreground">
              No active proxies
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>VPN</TableHead>
                  <TableHead>Namespace</TableHead>
                  <TableHead>Interface</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Idle</TableHead>
                  <TableHead>In</TableHead>
                  <TableHead>Out</TableHead>
                  <TableHead>Conns</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {namespaces.map((ns) => (
                  <TableRow key={ns.slug}>
                    <TableCell className="font-medium">
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => handleCopy(ns.vpnDisplayName)}
                          className="text-foreground hover:underline"
                        >
                          {ns.vpnDisplayName}
                        </button>
                        {status.random?.currentSlug === ns.slug && (
                          <Badge
                            variant="secondary"
                            className="bg-primary/20 text-primary border-primary/30 text-[9px] h-4"
                          >
                            RANDOM
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      <button
                        type="button"
                        onClick={() => handleCopy(ns.nsName)}
                        className="hover:underline"
                      >
                        {ns.nsName}
                      </button>
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      <button
                        type="button"
                        onClick={() => handleCopy(`veth-h-${ns.nsIndex}`)}
                        className="hover:underline"
                      >
                        veth-h-{ns.nsIndex}
                      </button>
                      <div className="text-[9px] text-muted-foreground/70">
                        Host interface (not VPN-routed)
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge
                        variant="outline"
                        className={cn(
                          "text-[10px] font-bold uppercase",
                          ns.status === "connected" &&
                            "bg-green-500/10 text-green-500 border-green-500/20",
                          ns.status === "starting" &&
                            "bg-yellow-500/10 text-yellow-500 border-yellow-500/20",
                          ns.status === "failed" &&
                            "bg-destructive/10 text-destructive border-destructive/20",
                        )}
                      >
                        {ns.status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      {formatIdle(ns.lastUsed)}
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      {formatBytes(ns.bytesIn || 0)}
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      {formatBytes(ns.bytesOut || 0)}
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      {ns.connections || 0}
                    </TableCell>
                    <TableCell className="text-right space-x-2">
                      <Button
                        variant={ns.pinned ? "secondary" : "outline"}
                        size="sm"
                        className="h-7 text-[10px]"
                        onClick={() => handlePin(ns.slug, ns.pinned)}
                      >
                        {ns.pinned ? "Pinned" : "Pin"}
                      </Button>
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-7 text-[10px]"
                        disabled={!ns.pinned}
                        title={
                          !ns.pinned
                            ? "Pin the proxy first to generate commands"
                            : "Generate command"
                        }
                        onClick={() => {
                          if (!ns.pinned) return;
                          const cmd = window.prompt(
                            "Enter the command to run inside this VPN namespace (e.g., qbittorrent):",
                          );
                          if (cmd) {
                            handleCopy(
                              `vpn-proxy tool command ${ns.slug} -- ${cmd}`,
                            );
                          }
                        }}
                      >
                        Cmd Gen
                      </Button>
                      <Button
                        variant="destructive"
                        size="sm"
                        className="h-7 text-[10px]"
                        onClick={() => handleDestroy(ns.slug)}
                      >
                        Stop
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ============================================================================
// VPNs Tab
// ============================================================================

function VpnsTab() {
  const [vpns, setVpns] = useState<VpnInfo[]>([]);
  const [filter, setFilter] = useState("");
  const [onlyWorking, setOnlyWorking] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const res = await api("/vpns");
    if (res.ok) setVpns(await res.json());
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const handleRefresh = async () => {
    await api("/vpns/refresh", { method: "POST" });
    load();
  };

  const filtered = vpns.filter((v) => {
    if (filter && !v.displayName.toLowerCase().includes(filter.toLowerCase()))
      return false;
    if (onlyWorking && v.testResult && !v.testResult.success) return false;
    return true;
  });

  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const toggleSelected = (slug: string) =>
    setSelected((prev) => ({ ...prev, [slug]: !prev[slug] }));

  const selectedSlugs = Object.entries(selected)
    .filter(([, v]) => v)
    .map(([k]) => k);

  const handleExport = async (format: string) => {
    const params = new URLSearchParams();
    if (onlyWorking) params.set("working", "true");
    if (selectedSlugs.length > 0) params.set("slugs", selectedSlugs.join(","));
    const res = await api(`/export/${format}?${params.toString()}`);
    const text = await res.text();
    navigator.clipboard.writeText(text);
    emitToast("Export copied");
  };

  if (loading)
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Loading VPNs...
      </div>
    );

  return (
    <Card className="glass-panel border-primary/20">
      <CardHeader className="pb-3">
        <CardTitle className="text-lg flex justify-between items-center">
          <span>Available VPNs ({filtered.length})</span>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleRefresh}
            className="h-8 w-8 p-0"
          >
            <RefreshCw className="w-4 h-4" />
          </Button>
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="flex flex-wrap items-center gap-4 mb-6">
          <Input
            placeholder="Filter by name..."
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="max-w-xs"
          />
          <div className="flex items-center space-x-2">
            <Switch
              id="working-only"
              checked={onlyWorking}
              onCheckedChange={setOnlyWorking}
            />
            <Label
              htmlFor="working-only"
              className="text-xs text-muted-foreground"
            >
              Working only
            </Label>
          </div>
          <div className="flex gap-2 ml-auto">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => handleExport("usernames")}
              className="gap-2 text-[11px]"
            >
              <Copy className="w-3.5 h-3.5" /> Slugs
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => handleExport("socks5")}
              className="gap-2 text-[11px]"
            >
              <Copy className="w-3.5 h-3.5" /> SOCKS5
            </Button>
          </div>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[40px]"></TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Country</TableHead>
              <TableHead>Last Test</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Latency</TableHead>
              <TableHead>IP</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.map((v) => (
              <TableRow key={v.slug}>
                <TableCell className="text-lg leading-none">
                  <input
                    type="checkbox"
                    checked={!!selected[v.slug]}
                    onChange={() => toggleSelected(v.slug)}
                  />
                </TableCell>
                <TableCell className="font-medium text-foreground">
                  <button
                    type="button"
                    onClick={() => handleCopy(v.displayName)}
                    className="hover:underline"
                  >
                    {v.displayName}
                  </button>
                </TableCell>
                <TableCell className="text-muted-foreground">
                  <button
                    type="button"
                    onClick={() => handleCopy(v.countryCode)}
                    className="hover:underline"
                  >
                    {v.countryCode}
                  </button>
                </TableCell>
                <TableCell className="text-muted-foreground text-[11px]">
                  {v.testResult ? formatAgo(v.testResult.testedAt) : "Never"}
                </TableCell>
                <TableCell>
                  {v.testResult ? (
                    v.testResult.success ? (
                      <CheckCircle2 className="w-4 h-4 text-green-500" />
                    ) : (
                      <XCircle className="w-4 h-4 text-destructive" />
                    )
                  ) : (
                    <span className="text-muted-foreground">--</span>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground tabular-nums">
                  {v.testResult?.latencyMs
                    ? `${v.testResult.latencyMs}ms`
                    : "--"}
                </TableCell>
                <TableCell className="text-muted-foreground font-mono text-[10px]">
                  <button
                    type="button"
                    onClick={() =>
                      v.testResult?.ip && handleCopy(v.testResult.ip)
                    }
                    className="hover:underline"
                  >
                    {v.testResult?.ip || "--"}
                  </button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

// ============================================================================
// Testing Tab
// ============================================================================

function TestingTab() {
  const [testing, setTesting] = useState(false);
  const [progress, setProgress] = useState({ completed: 0, total: 0 });
  const [results, setResults] = useState<TestResults | null>(null);
  const [currentSlug, setCurrentSlug] = useState<string | null>(null);

  const loadResults = useCallback(async () => {
    const res = await api("/test-results");
    if (res.ok) setResults(await res.json());
  }, []);

  useEffect(() => {
    loadResults();
    api("/test-progress")
      .then((r) => (r.ok ? r.json() : null))
      .then((data: TestProgress | null) => {
        if (data?.running && data.progress) {
          setTesting(true);
          setProgress(data.progress);
          setCurrentSlug(data.currentSlug || null);
        }
      });
  }, [loadResults]);

  const handleTestAll = async () => {
    setTesting(true);
    setProgress({ completed: 0, total: 0 });

    const reader = await fetch("/api/test-all", {
      headers: API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {},
    });

    const rdr = reader.body?.getReader();
    if (!rdr) {
      setTesting(false);
      return;
    }

    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await rdr.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (line.startsWith("data: ")) {
          try {
            const data = JSON.parse(line.slice(6));
            if (data.done) {
              setTesting(false);
              setProgress({ completed: 0, total: 0 });
              loadResults();
              return;
            }
            if (typeof data.completed === "number") {
              setProgress({ completed: data.completed, total: data.total });
              setCurrentSlug(data.result?.slug || null);
            }
          } catch {}
        }
      }
    }
    setTesting(false);
    setProgress({ completed: 0, total: 0 });
    setCurrentSlug(null);
    loadResults();
  };

  const totalTests = results ? Object.keys(results.results || {}).length : 0;
  const passed = results
    ? Object.values(results.results || {}).filter((r: any) => r.success).length
    : 0;
  const failed = totalTests - passed;

  return (
    <Card className="glass-panel border-primary/20">
      <CardHeader className="pb-3">
        <CardTitle className="text-lg">Proxy Health Testing</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
            <div className="text-2xl font-bold text-green-500">{passed}</div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Passed
            </div>
          </div>
          <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
            <div className="text-2xl font-bold text-destructive">{failed}</div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Failed
            </div>
          </div>
          <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
            <div className="text-2xl font-bold text-foreground">
              {totalTests}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Total Tested
            </div>
          </div>
          <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
            <div className="text-sm font-bold text-foreground">
              {results?.lastFullTestAt
                ? formatAgo(results.lastFullTestAt)
                : "Never"}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Last Full Test
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <div className="flex gap-3">
            <Button
              variant="default"
              onClick={handleTestAll}
              disabled={testing}
              className="min-w-[200px]"
            >
              {testing
                ? `Testing ${progress.completed}/${progress.total}...`
                : "Test All Proxies"}
            </Button>
          </div>

          {testing && (
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <Progress
                  value={
                    progress.total
                      ? (progress.completed / progress.total) * 100
                      : 0
                  }
                  className="flex-1"
                />
                <Button
                  variant="destructive"
                  size="sm"
                  onClick={async () => {
                    await api("/test-all/stop", { method: "POST" });
                  }}
                  className="shrink-0"
                >
                  Stop
                </Button>
              </div>
              {currentSlug && (
                <div className="text-[10px] text-muted-foreground">
                  Testing: {currentSlug}
                </div>
              )}
              <div className="text-right text-[10px] text-muted-foreground tabular-nums">
                {Math.round(
                  progress.total
                    ? (progress.completed / progress.total) * 100
                    : 0,
                )}
                %
              </div>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

// ============================================================================
// Auth Tab
// ============================================================================

function AuthTab() {
  const [response, setResponse] = useState<AuthPatchListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  // Per-row selection state: ovpnPath → boolean
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  // Bulk inputs per group
  const [passwordOnlyPassword, setPasswordOnlyPassword] = useState("");
  const [usernameValue, setUsernameValue] = useState("");
  const [usernamePasswordValue, setUsernamePasswordValue] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const res = await api("/auth-patches");
    if (!res.ok) {
      setLoading(false);
      return;
    }
    const data: AuthPatchListResponse = await res.json();
    setResponse(data);
    // Initialize selections from `selectedByDefault` on patchable rows only
    const initial: Record<string, boolean> = {};
    for (const row of data.rows) {
      if (row.canPatch) {
        initial[row.ovpnPath] = row.selectedByDefault;
      }
    }
    setSelected(initial);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const toggleRow = (ovpnPath: string) =>
    setSelected((prev) => ({ ...prev, [ovpnPath]: !prev[ovpnPath] }));

  const getGroupRows = (
    groupKey: "passwordOnly" | "usernamePassword" | "ambiguous",
  ) => response?.rows.filter((row) => row.group === groupKey) ?? [];

  const patchOne = async (row: AuthPatchCandidate) => {
    if (!row.canPatch) {
      emitToast("Cannot patch: requires manual review");
      return;
    }
    setSubmitting(true);
    const body: { ovpnPath: string; username?: string; password: string } = {
      ovpnPath: row.ovpnPath,
      password:
        row.inputMode === "password-only"
          ? passwordOnlyPassword
          : usernamePasswordValue,
    };
    if (row.inputMode === "username-password") {
      body.username = usernameValue;
    }
    const res = await api("/auth-patches/apply-one", {
      method: "POST",
      body: JSON.stringify(body),
    });
    setSubmitting(false);
    if (res.ok) {
      emitToast(`Patched ${row.displayName}`);
      load();
    } else {
      const err = await res.json().catch(() => null);
      emitToast(err?.message || "Failed to patch");
    }
  };

  const patchBulk = async (groupKey: "passwordOnly" | "usernamePassword") => {
    const rows = getGroupRows(groupKey);
    const patchable = rows.filter(
      (row) => selected[row.ovpnPath] && row.canPatch,
    );
    if (patchable.length === 0) {
      emitToast("Select at least one patchable config");
      return;
    }
    if (groupKey === "passwordOnly" && !passwordOnlyPassword.trim()) {
      emitToast("Enter a password first");
      return;
    }
    if (
      groupKey === "usernamePassword" &&
      (!usernameValue.trim() || !usernamePasswordValue.trim())
    ) {
      emitToast("Enter both username and password");
      return;
    }
    setSubmitting(true);
    const res = await api("/auth-patches/apply", {
      method: "POST",
      body: JSON.stringify({
        items: patchable.map((row) => ({
          ovpnPath: row.ovpnPath,
          username:
            row.inputMode === "username-password" ? usernameValue : undefined,
          password:
            groupKey === "passwordOnly"
              ? passwordOnlyPassword
              : usernamePasswordValue,
        })),
      }),
    });
    setSubmitting(false);
    if (res.ok) {
      const body = await res.json();
      emitToast(
        `Patched ${body.totals.patched}/${body.totals.requested} configs`,
      );
      if (groupKey === "passwordOnly") setPasswordOnlyPassword("");
      else {
        setUsernameValue("");
        setUsernamePasswordValue("");
      }
      load();
    } else {
      emitToast("Bulk patch failed");
    }
  };

  if (loading) {
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Inspecting OpenVPN auth files...
      </div>
    );
  }

  if (!response) {
    return (
      <div className="py-20 text-center text-muted-foreground">
        Failed to load auth patch data.
      </div>
    );
  }

  const { summary, groups, rows } = response;

  return (
    <div className="space-y-6">
      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="glass-soft border-border/50">
          <CardContent className="p-4 text-center">
            <div className="text-2xl font-bold text-foreground">
              {summary.totalCandidates}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Total Candidates
            </div>
          </CardContent>
        </Card>
        <Card className="glass-soft border-border/50">
          <CardContent className="p-4 text-center">
            <div className="text-2xl font-bold text-green-500">
              {summary.patchableCandidates}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Patchable
            </div>
          </CardContent>
        </Card>
        <Card className="glass-soft border-border/50">
          <CardContent className="p-4 text-center">
            <div className="text-2xl font-bold text-yellow-500">
              {summary.ambiguousCandidates}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Needs Review
            </div>
          </CardContent>
        </Card>
        <Card className="glass-soft border-border/50">
          <CardContent className="p-4 text-center">
            <div className="text-2xl font-bold text-accent">
              {summary.passwordOnlyCandidates +
                summary.usernamePasswordCandidates}
            </div>
            <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
              Auth-User-Pass
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Refresh button */}
      <div className="flex justify-end">
        <Button variant="outline" size="sm" onClick={load} className="gap-2">
          <RefreshCw className="w-3.5 h-3.5" /> Refresh
        </Button>
      </div>

      {/* Password-only group */}
      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center justify-between">
            <span>Password-only auth files</span>
            <Badge
              variant="secondary"
              className="bg-primary/15 text-primary border-primary/25"
            >
              {groups.passwordOnly?.count ?? 0}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-xs text-muted-foreground">
            These configs already point at a username-only auth file
            (auth-user-pass with existing username). Only the missing password
            needs to be written.
          </p>
          {groups.passwordOnly?.count === 0 ? (
            <p className="text-sm text-muted-foreground">
              No password-only patches needed.
            </p>
          ) : (
            <>
              <div className="space-y-2">
                {getGroupRows("passwordOnly").map((row) => (
                  <div
                    key={row.ovpnPath}
                    className="flex items-start gap-3 rounded-lg border border-border/50 p-3 glass-soft"
                  >
                    <input
                      type="checkbox"
                      checked={!!selected[row.ovpnPath]}
                      onChange={() => toggleRow(row.ovpnPath)}
                      className="mt-0.5"
                      disabled={!row.canPatch}
                    />
                    <div className="min-w-0 flex-1 space-y-1">
                      <div className="text-sm font-medium">
                        {row.displayName}
                      </div>
                      <div className="text-[11px] text-muted-foreground break-all">
                        {row.ovpnPath}
                      </div>
                      <div className="text-[11px] text-muted-foreground">
                        Username:{" "}
                        <span className="font-mono">
                          {row.usernameHint || "—"}
                        </span>
                      </div>
                    </div>
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={!row.canPatch || submitting}
                      onClick={() => patchOne(row)}
                      className="gap-1 h-7 text-[10px]"
                    >
                      Patch
                    </Button>
                  </div>
                ))}
              </div>
              <div className="flex flex-col gap-3 md:flex-row md:items-end">
                <div className="flex-1 space-y-1">
                  <Label className="text-sm">Password</Label>
                  <Input
                    type="password"
                    value={passwordOnlyPassword}
                    onChange={(e) => setPasswordOnlyPassword(e.target.value)}
                    onKeyDown={(e) =>
                      e.key === "Enter" &&
                      !submitting &&
                      patchBulk("passwordOnly")
                    }
                    placeholder="Enter password for selected configs"
                  />
                </div>
                <Button
                  onClick={() => patchBulk("passwordOnly")}
                  disabled={submitting}
                  className="md:min-w-[140px]"
                >
                  Apply Selected
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {/* Username + password group */}
      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center justify-between">
            <span>Username + password auth files</span>
            <Badge
              variant="secondary"
              className="bg-accent/15 text-accent border-accent/25"
            >
              {groups.usernamePassword?.count ?? 0}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-xs text-muted-foreground">
            These configs have a bare{" "}
            <code className="text-xs bg-muted/50 px-1 rounded">
              auth-user-pass
            </code>{" "}
            directive or a missing/unusable auth file. Both credentials are
            required before they work in OpenVPN.
          </p>
          {groups.usernamePassword?.count === 0 ? (
            <p className="text-sm text-muted-foreground">
              No username/password patches needed.
            </p>
          ) : (
            <>
              <div className="space-y-2">
                {getGroupRows("usernamePassword").map((row) => (
                  <div
                    key={row.ovpnPath}
                    className="flex items-start gap-3 rounded-lg border border-border/50 p-3 glass-soft"
                  >
                    <input
                      type="checkbox"
                      checked={!!selected[row.ovpnPath]}
                      onChange={() => toggleRow(row.ovpnPath)}
                      className="mt-0.5"
                      disabled={!row.canPatch}
                    />
                    <div className="min-w-0 flex-1 space-y-1">
                      <div className="text-sm font-medium">
                        {row.displayName}
                      </div>
                      <div className="text-[11px] text-muted-foreground break-all">
                        {row.ovpnPath}
                      </div>
                      <div className="text-[11px] text-muted-foreground">
                        {row.reason}
                      </div>
                    </div>
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={!row.canPatch || submitting}
                      onClick={() => patchOne(row)}
                      className="gap-1 h-7 text-[10px]"
                    >
                      Patch
                    </Button>
                  </div>
                ))}
              </div>
              <div className="grid gap-3 md:grid-cols-[1fr_1fr_auto] md:items-end">
                <div className="space-y-1">
                  <Label className="text-sm">Username</Label>
                  <Input
                    value={usernameValue}
                    onChange={(e) => setUsernameValue(e.target.value)}
                    placeholder="Enter username"
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-sm">Password</Label>
                  <Input
                    type="password"
                    value={usernamePasswordValue}
                    onChange={(e) => setUsernamePasswordValue(e.target.value)}
                    onKeyDown={(e) =>
                      e.key === "Enter" &&
                      !submitting &&
                      patchBulk("usernamePassword")
                    }
                    placeholder="Enter password"
                  />
                </div>
                <Button
                  onClick={() => patchBulk("usernamePassword")}
                  disabled={submitting}
                  className="md:min-w-[140px]"
                >
                  Apply Selected
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {/* Manual review group */}
      {groups.ambiguous?.count > 0 && (
        <Card className="glass-panel border-primary/20">
          <CardHeader className="pb-3">
            <CardTitle className="text-lg flex items-center justify-between">
              <span>Manual review required</span>
              <Badge
                variant="secondary"
                className="bg-destructive/15 text-destructive border-destructive/25"
              >
                {groups.ambiguous.count}
              </Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            <p className="text-xs text-muted-foreground mb-4">
              These configs have an ambiguous or unusable auth-user-pass layout
              and cannot be patched automatically. Review the OpenVPN
              configuration and resolve manually.
            </p>
            {getGroupRows("ambiguous").map((row) => (
              <div
                key={row.ovpnPath}
                className="rounded-lg border border-border/50 p-3 glass-soft opacity-80"
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1 space-y-1">
                    <div className="text-sm font-medium">{row.displayName}</div>
                    <div className="text-[11px] text-muted-foreground break-all">
                      {row.ovpnPath}
                    </div>
                    <div className="text-[11px] text-muted-foreground flex items-center gap-1">
                      <ShieldAlert className="w-3 h-3" />
                      {row.reason}
                    </div>
                  </div>
                  <Badge
                    variant="outline"
                    className="bg-destructive/10 text-destructive border-destructive/20 shrink-0"
                  >
                    Manual review
                  </Badge>
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

// ============================================================================
// Settings Tab
// ============================================================================

function SettingsTab() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [tiers, setTiers] = useState<
    { minActive: number; timeoutSeconds: number }[]
  >([]);
  const [results, setResults] = useState<TestResults | null>(null);

  useEffect(() => {
    api("/settings")
      .then((r) => r.json())
      .then((s) => {
        setSettings(s);
        setTiers(s.idleTimeoutTiers);
      });
    api("/test-results")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setResults(data));
  }, []);

  // Sync tiers with settings when settings change externally
  useEffect(() => {
    if (settings) {
      setTiers(settings.idleTimeoutTiers);
    }
  }, [settings?.idleTimeoutTiers]);

  const update = async (partial: any) => {
    const res = await api("/settings", {
      method: "PUT",
      body: JSON.stringify(partial),
    });
    if (res.ok) setSettings(await res.json());
  };

  const saveTiers = (newTiers: typeof tiers) => {
    setTiers(newTiers);
    update({ idleTimeoutTiers: newTiers });
  };

  const updateTier = (
    index: number,
    field: "minActive" | "timeoutSeconds",
    value: number,
  ) => {
    const newTiers = [...tiers];
    newTiers[index] = { ...newTiers[index], [field]: value };
    saveTiers(newTiers);
  };

  const removeTier = (index: number) => {
    saveTiers(tiers.filter((_, i) => i !== index));
  };

  const addTier = () => {
    saveTiers([...tiers, { minActive: tiers.length, timeoutSeconds: 60 }]);
  };

  const handleReset = async () => {
    const res = await api("/settings/reset", { method: "POST" });
    if (res.ok) {
      const s = await res.json();
      setSettings(s);
      setTiers(s.idleTimeoutTiers);
    }
  };

  function NextTestCountdown({
    settings,
    results,
  }: {
    settings: Settings;
    results: TestResults | null;
  }) {
    const [now, setNow] = useState(Date.now());
    useEffect(() => {
      const interval = setInterval(() => setNow(Date.now()), 1000);
      return () => clearInterval(interval);
    }, []);

    if (!settings.testing.enabled || !results?.lastFullTestAt) {
      return (
        <span className="text-muted-foreground text-[11px]">
          No test run yet
        </span>
      );
    }

    const nextAt =
      results.nextFullTestAt ||
      results.lastFullTestAt + settings.testing.intervalHours * 3600 * 1000;
    const diff = nextAt - now;

    if (diff <= 0) {
      return (
        <span className="text-yellow-500 text-[11px] font-medium">Overdue</span>
      );
    }

    const hours = Math.floor(diff / 3600000);
    const mins = Math.floor((diff % 3600000) / 60000);
    const secs = Math.floor((diff % 60000) / 1000);
    const parts = [];
    if (hours > 0) parts.push(`${hours}h`);
    if (mins > 0) parts.push(`${mins}m`);
    parts.push(`${secs}s`);

    return (
      <span className="text-muted-foreground text-[11px] tabular-nums">
        {parts.join(" ")}
      </span>
    );
  }

  if (!settings)
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Loading settings...
      </div>
    );

  return (
    <div className="space-y-6">
      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center justify-between">
            <span>Testing Settings</span>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between py-2 border-b border-border/40">
            <div className="space-y-1">
              <Label className="text-sm">Auto-test enabled</Label>
              <p className="text-[10px] text-muted-foreground">
                Automatically test all proxies on a schedule
              </p>
            </div>
            <Switch
              checked={settings.testing.enabled}
              onCheckedChange={(checked) =>
                update({ testing: { enabled: checked } })
              }
            />
          </div>

          {settings.testing.enabled && (
            <div className="flex items-center justify-between py-2 border-b border-border/40">
              <div className="space-y-1">
                <Label className="text-sm">Next auto-test</Label>
                <p className="text-[10px] text-muted-foreground">
                  Time until next scheduled test run
                </p>
              </div>
              <NextTestCountdown settings={settings} results={results} />
            </div>
          )}

          <div className="flex items-center justify-between py-2 border-b border-border/40">
            <div className="space-y-1">
              <Label className="text-sm">Test interval (hours)</Label>
              <p className="text-[10px] text-muted-foreground">
                Hours between automated full tests
              </p>
            </div>
            <Input
              type="number"
              value={settings.testing.intervalHours}
              onChange={(e) =>
                update({ testing: { intervalHours: Number(e.target.value) } })
              }
              className="w-24 text-right"
            />
          </div>

          <div className="flex items-center justify-between py-2 border-b border-border/40">
            <div className="space-y-1">
              <Label className="text-sm">Test gap (seconds)</Label>
              <p className="text-[10px] text-muted-foreground">
                Wait time between testing individual VPNs
              </p>
            </div>
            <Input
              type="number"
              value={settings.testing.testGapSeconds}
              onChange={(e) =>
                update({ testing: { testGapSeconds: Number(e.target.value) } })
              }
              className="w-24 text-right"
            />
          </div>

          <div className="flex items-center justify-between py-2">
            <div className="space-y-1">
              <Label className="text-sm">Exclude failed from random</Label>
              <p className="text-[10px] text-muted-foreground">
                Skip VPNs that failed their last test
              </p>
            </div>
            <Switch
              checked={settings.testing.excludeFailedFromRandom}
              onCheckedChange={(checked) =>
                update({ testing: { excludeFailedFromRandom: checked } })
              }
            />
          </div>
        </CardContent>
      </Card>

      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Pattern Matching</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between py-2">
            <div className="space-y-1">
              <Label className="text-sm">Pattern matching enabled</Label>
              <p className="text-[10px] text-muted-foreground">
                Allow "GB", "Manchester", "Ceibo" as proxy usernames
              </p>
            </div>
            <Switch
              checked={settings.patternParsing.enabled}
              onCheckedChange={(checked) =>
                update({ patternParsing: { enabled: checked } })
              }
            />
          </div>
        </CardContent>
      </Card>

      <Card className="glass-panel border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center justify-between">
            <span>Idle Timeout Tiers</span>
            <Button
              variant="outline"
              size="sm"
              onClick={addTier}
              className="h-7 gap-1 text-[10px]"
            >
              <Plus className="w-3 h-3" /> Add Tier
            </Button>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Min Active</TableHead>
                <TableHead>Timeout (s)</TableHead>
                <TableHead>Human Readable</TableHead>
                <TableHead className="w-[50px]"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {tiers.map((tier, i) => (
                <TableRow key={i}>
                  <TableCell>
                    <Input
                      type="number"
                      value={tier.minActive}
                      onChange={(e) =>
                        updateTier(i, "minActive", Number(e.target.value))
                      }
                      className="w-20 h-8 text-sm text-right"
                      min={0}
                    />
                  </TableCell>
                  <TableCell>
                    <Input
                      type="number"
                      value={tier.timeoutSeconds}
                      onChange={(e) =>
                        updateTier(i, "timeoutSeconds", Number(e.target.value))
                      }
                      className="w-24 h-8 text-sm text-right"
                      min={1}
                    />
                  </TableCell>
                  <TableCell className="text-muted-foreground text-sm">
                    {tier.timeoutSeconds >= 60
                      ? `${Math.floor(tier.timeoutSeconds / 60)}m ${tier.timeoutSeconds % 60}s`
                      : `${tier.timeoutSeconds}s`}
                  </TableCell>
                  <TableCell>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => removeTier(i)}
                      className="h-7 w-7 p-0 text-destructive hover:text-destructive text-lg"
                    >
                      ×
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>

          <div className="mt-8 flex justify-end">
            <Button
              variant="destructive"
              size="sm"
              onClick={handleReset}
              className="gap-2"
            >
              <ShieldAlert className="w-3.5 h-3.5" /> Reset to Defaults
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function ApiTab() {
  const [openapiUrl, setOpenapiUrl] = useState<{
    docsUrl: string;
    specUrl: string;
  } | null>(null);

  useEffect(() => {
    api("/openapi-url")
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => data && setOpenapiUrl(data));
  }, []);

  const copyPrompt = async (text: string) => {
    await navigator.clipboard.writeText(text);
    emitToast("Prompt copied");
  };

  const baseUrl = openapiUrl?.specUrl || "";
  const prompts = [
    {
      title: "Proxy Manager (OpenAPI)",
      text: `You are an API client. Use the VPN Proxy OpenAPI spec at ${baseUrl} to manage proxies. Always include Authorization: Bearer <API_KEY>. List active namespaces, pin a namespace by slug, and export SOCKS5 URLs.`,
    },
    {
      title: "Health & Testing",
      text: `Use the OpenAPI spec at ${baseUrl} to run proxy tests. Trigger /api/test-all, stream progress, and summarize failed proxies. Include Authorization: Bearer <API_KEY>.`,
    },
    {
      title: "Settings & Timeouts",
      text: `Use the OpenAPI spec at ${baseUrl} to read and update settings. Adjust idleTimeoutTiers and testing interval. Include Authorization: Bearer <API_KEY>.`,
    },
  ];

  return (
    <Card className="glass-panel border-primary/20">
      <CardHeader className="pb-3">
        <CardTitle className="text-lg">API Management</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex flex-wrap gap-3">
          <Button
            variant="secondary"
            onClick={() =>
              openapiUrl?.docsUrl && window.open(openapiUrl.docsUrl, "_blank")
            }
          >
            Open API Docs
          </Button>
          <Button
            variant="outline"
            onClick={() =>
              openapiUrl?.specUrl && window.open(openapiUrl.specUrl, "_blank")
            }
          >
            Open OpenAPI JSON
          </Button>
        </div>

        <div className="space-y-4">
          {prompts.map((prompt) => (
            <Card key={prompt.title} className="glass-soft border-primary/10">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm">{prompt.title}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="text-xs text-muted-foreground whitespace-pre-wrap">
                  {prompt.text}
                </div>
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => copyPrompt(prompt.text)}
                >
                  Copy Prompt
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

// ============================================================================
// Main App
// ============================================================================

function App() {
  const [authenticated, setAuthenticated] = useState(!!API_KEY);
  const [tab, setTab] = useState("dashboard");
  const [status, setStatus] = useState<ProxyStatus | null>(null);
  const [isDark, setIsDark] = useState(() => {
    const stored = localStorage.getItem("vpn-proxy-theme");
    if (stored === "light") return false;
    if (stored === "dark") return true;
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  });

  const handleAuth = (key: string) => {
    API_KEY = key;
    localStorage.setItem("vpn-proxy-api-key", key);
    setAuthenticated(true);
  };

  // SSE for real-time status updates
  useEffect(() => {
    if (!authenticated) return;

    // Initial fetch
    api("/status")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => d && setStatus(d));

    // SSE stream with fetch (allows auth headers)
    let cancelled = false;
    const connectSSE = async () => {
      try {
        const res = await fetch("/api/sse/status", {
          headers: API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {},
        });
        const reader = res.body?.getReader();
        if (!reader) return;

        const decoder = new TextDecoder();
        let buffer = "";

        while (!cancelled) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";

          for (const line of lines) {
            if (line.startsWith("data: ")) {
              try {
                const data = JSON.parse(line.slice(6));
                if (data.namespaces)
                  setStatus((prev) => (prev ? { ...prev, ...data } : data));
              } catch {}
            }
          }
        }
      } catch {
        // Reconnect after delay
        if (!cancelled) setTimeout(connectSSE, 3000);
      }
    };

    connectSSE();
    return () => {
      cancelled = true;
    };
  }, [authenticated]);

  useEffect(() => {
    document.documentElement.classList.remove("dark", "light");
    document.documentElement.classList.add(isDark ? "dark" : "light");
    localStorage.setItem("vpn-proxy-theme", isDark ? "dark" : "light");
  }, [isDark]);

  if (!authenticated) return <AuthScreen onAuth={handleAuth} />;

  return (
    <div className="min-h-screen bg-background text-foreground selection:bg-primary/30">
      <ToastHost />
      <div className="max-w-6xl mx-auto px-4 py-6 space-y-8">
        <header className="flex flex-col md:flex-row justify-between items-center gap-4 p-4 glass-panel rounded-2xl">
          <div className="flex flex-col">
            <h1 className="text-xl font-black tracking-tight text-primary uppercase italic">
              VPN <span className="text-accent not-italic">Proxy</span> Manager
            </h1>
            <div className="flex items-center gap-3 text-[10px] uppercase tracking-widest font-bold text-muted-foreground">
              <span>Desktop Interface</span>
              <span className="chip">Active</span>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Button
              variant="outline"
              size="icon"
              onClick={() => setIsDark(!isDark)}
              className="rounded-xl border-primary/20 hover:border-accent hover:text-accent transition-all duration-300"
            >
              {isDark ? (
                <Sun className="w-4 h-4" />
              ) : (
                <Moon className="w-4 h-4" />
              )}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => {
                API_KEY = "";
                localStorage.removeItem("vpn-proxy-api-key");
                setAuthenticated(false);
              }}
              className="gap-2 rounded-xl"
            >
              <LogOut className="w-3.5 h-3.5" /> Logout
            </Button>
          </div>
        </header>

        <Tabs value={tab} onValueChange={setTab} className="space-y-6">
          <div className="flex justify-center md:justify-start overflow-x-auto pb-1">
            <TabsList className="glass-panel h-auto p-1 rounded-xl">
              {["dashboard", "vpns", "auth", "testing", "settings", "api"].map(
                (t) => (
                  <TabsTrigger
                    key={t}
                    value={t}
                    className="px-6 py-2.5 rounded-lg data-[state=active]:bg-primary data-[state=active]:text-primary-foreground transition-all duration-300 capitalize text-xs font-bold tracking-wide"
                  >
                    {t}
                  </TabsTrigger>
                ),
              )}
            </TabsList>
          </div>

          <div className="animate-in fade-in slide-in-from-bottom-2 duration-500">
            <TabsContent value="dashboard">
              <DashboardTab status={status} />
            </TabsContent>
            <TabsContent value="vpns">
              <VpnsTab />
            </TabsContent>
            <TabsContent value="auth">
              <AuthTab />
            </TabsContent>
            <TabsContent value="testing">
              <TestingTab />
            </TabsContent>
            <TabsContent value="settings">
              <SettingsTab />
            </TabsContent>
            <TabsContent value="api">
              <ApiTab />
            </TabsContent>
          </div>
        </Tabs>

        <footer className="pt-10 pb-6 text-center text-[10px] text-muted-foreground uppercase tracking-[0.2em] font-medium opacity-50">
          Built with Shadcn/UI • Tailwind v4 • BunJS
        </footer>
      </div>
    </div>
  );
}

// ============================================================================
// Mount
// ============================================================================

const root = createRoot(document.getElementById("root")!);
root.render(<App />);
