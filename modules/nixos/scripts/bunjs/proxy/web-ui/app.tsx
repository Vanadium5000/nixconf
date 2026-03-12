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
} from "lucide-react";

// @ts-nocheck — Browser-only TSX; tsconfig targets node, not DOM.
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
    excludeFailedFromRandom: boolean;
    lastFullTestAt: number | null;
  };
  webUi: { port: number };
}

interface TestResults {
  results: Record<
    string,
    { success: boolean; testedAt: number; [key: string]: any }
  >;
  lastFullTestAt: number | null;
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

  return (
    <div className="space-y-6">
      <Card className="border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg flex items-center gap-2">
            Overview
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.activeCount}
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                Active Proxies
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.currentTimeoutSeconds}s
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                Idle Timeout
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
              <div className="text-2xl font-bold text-foreground">
                {status.socks5Port}
              </div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground mt-1">
                SOCKS5 Port
              </div>
            </div>
            <div className="flex flex-col items-center justify-center p-4 bg-muted/30 rounded-lg border border-border/50">
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

      <Card className="border-primary/20">
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
                        <span className="text-foreground">
                          {ns.vpnDisplayName}
                        </span>
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
                    <TableCell className="text-right">
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

  const handleExport = async (format: string) => {
    const res = await api(
      `/export/${format}${onlyWorking ? "?working=true" : ""}`,
    );
    const text = await res.text();
    navigator.clipboard.writeText(text);
  };

  if (loading)
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Loading VPNs...
      </div>
    );

  return (
    <Card className="border-primary/20">
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
                <TableCell className="text-lg leading-none">{v.flag}</TableCell>
                <TableCell className="font-medium text-foreground">
                  {v.displayName}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {v.countryCode}
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
                  {v.testResult?.ip || "--"}
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

  const loadResults = useCallback(async () => {
    const res = await api("/test-results");
    if (res.ok) setResults(await res.json());
  }, []);

  useEffect(() => {
    loadResults();
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
              loadResults();
              return;
            }
            if (data.completed) {
              setProgress({ completed: data.completed, total: data.total });
            }
          } catch {}
        }
      }
    }
    setTesting(false);
    loadResults();
  };

  const totalTests = results ? Object.keys(results.results || {}).length : 0;
  const passed = results
    ? Object.values(results.results || {}).filter((r: any) => r.success).length
    : 0;
  const failed = totalTests - passed;

  return (
    <Card className="border-primary/20">
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
          <Button
            variant="default"
            onClick={handleTestAll}
            disabled={testing}
            className="w-full md:w-auto min-w-[200px]"
          >
            {testing
              ? `Testing ${progress.completed}/${progress.total}...`
              : "Test All Proxies"}
          </Button>

          {testing && (
            <div className="space-y-2">
              <Progress
                value={
                  progress.total
                    ? (progress.completed / progress.total) * 100
                    : 0
                }
              />
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
// Settings Tab
// ============================================================================

function SettingsTab() {
  const [settings, setSettings] = useState<Settings | null>(null);

  useEffect(() => {
    api("/settings")
      .then((r) => r.json())
      .then(setSettings);
  }, []);

  const update = async (partial: any) => {
    const res = await api("/settings", {
      method: "PUT",
      body: JSON.stringify(partial),
    });
    if (res.ok) setSettings(await res.json());
  };

  const handleReset = async () => {
    const res = await api("/settings/reset", { method: "POST" });
    if (res.ok) setSettings(await res.json());
  };

  if (!settings)
    return (
      <div className="py-20 text-center text-muted-foreground animate-pulse">
        Loading settings...
      </div>
    );

  return (
    <div className="space-y-6">
      <Card className="border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Testing Settings</CardTitle>
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

      <Card className="border-primary/20">
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

      <Card className="border-primary/20">
        <CardHeader className="pb-3">
          <CardTitle className="text-lg">Idle Timeout Tiers</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Min Active</TableHead>
                <TableHead>Timeout (s)</TableHead>
                <TableHead>Human Readable</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {settings.idleTimeoutTiers
                .sort((a, b) => a.minActive - b.minActive)
                .map((tier, i) => (
                  <TableRow key={i}>
                    <TableCell className="font-medium">
                      {tier.minActive}+ proxies
                    </TableCell>
                    <TableCell className="text-muted-foreground tabular-nums">
                      {tier.timeoutSeconds}s
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {Math.floor(tier.timeoutSeconds / 60)}m{" "}
                      {tier.timeoutSeconds % 60}s
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

// ============================================================================
// Main App
// ============================================================================

function App() {
  const [authenticated, setAuthenticated] = useState(!!API_KEY);
  const [tab, setTab] = useState("dashboard");
  const [status, setStatus] = useState<ProxyStatus | null>(null);
  const [isDark, setIsDark] = useState(true);

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
                if (data.namespaces) setStatus(data);
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
    document.documentElement.className = isDark ? "dark" : "light";
  }, [isDark]);

  if (!authenticated) return <AuthScreen onAuth={handleAuth} />;

  return (
    <div className="min-h-screen bg-background text-foreground selection:bg-primary/30">
      <div className="max-w-6xl mx-auto px-4 py-6 space-y-8">
        <header className="flex flex-col md:flex-row justify-between items-center gap-4 p-6 bg-card border border-primary/20 rounded-2xl glass shadow-lg">
          <div className="flex flex-col">
            <h1 className="text-2xl font-black tracking-tight text-primary uppercase italic">
              VPN <span className="text-accent not-italic">Proxy</span> Manager
            </h1>
            <p className="text-[10px] text-muted-foreground uppercase tracking-widest font-bold">
              Liquid Glass Interface
            </p>
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
            <TabsList className="bg-card/50 border border-primary/10 h-auto p-1 rounded-xl glass">
              {["dashboard", "vpns", "testing", "settings"].map((t) => (
                <TabsTrigger
                  key={t}
                  value={t}
                  className="px-6 py-2.5 rounded-lg data-[state=active]:bg-primary data-[state=active]:text-primary-foreground transition-all duration-300 capitalize text-xs font-bold tracking-wide"
                >
                  {t}
                </TabsTrigger>
              ))}
            </TabsList>
          </div>

          <div className="animate-in fade-in slide-in-from-bottom-2 duration-500">
            <TabsContent value="dashboard">
              <DashboardTab status={status} />
            </TabsContent>
            <TabsContent value="vpns">
              <VpnsTab />
            </TabsContent>
            <TabsContent value="testing">
              <TestingTab />
            </TabsContent>
            <TabsContent value="settings">
              <SettingsTab />
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
