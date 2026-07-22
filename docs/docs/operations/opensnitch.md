---
title: OpenSnitch workflow
---

Graphical hosts run OpenSnitch from `modules/nixos/desktop/opensnitch.nix`. The module owns daemon settings, the private UI socket, the typed rule schema, curated default rules, and the authenticated bypass wrapper.

## Runtime model

```mermaid
flowchart LR
  nix[Nix module] --> tmpfiles[systemd-tmpfiles]
  nix --> prest[opensnitchd preStart]
  tmpfiles --> rules[/var/lib/opensnitch/rules/*.json]
  prest --> rules
  ui[opensnitch-ui] --> rules
  rules --> daemon[opensnitchd eBPF + nftables]
```

- Daemon config path: `/var/lib/opensnitch/default-config.json`.
- Rule path: `/var/lib/opensnitch/rules`.
- UI socket: `/run/user/<uid>/opensnitch/osui.sock`, wrapped into `opensnitch-ui`.
- Persisted state: `/var/lib/opensnitch` and `~/.config/opensnitch` via impermanence.
- Reset behavior: Nix writes rule JSON with `C+` tmpfiles entries and `opensnitchd.preStart` deletes existing `*.json` before reinstalling Nix-managed rules.

The files are still mutable while the system is running, so the UI can inspect or temporarily edit them. Treat UI edits as scratch state. If a rule should survive the next activation or service start, migrate it into `services.opensnitch.mutableRules`.

## Rule schema

`services.opensnitch.mutableRules` is an attribute set of OpenSnitch JSON rules with typed fields and freeform escape hatches for upstream additions:

```nix
services.opensnitch.mutableRules."060-allow-example" = {
  action = "allow";
  description = "Allow one immutable Nix-packaged client to one HTTPS API.";
  duration = "always";
  precedence = false;
  operator = {
    type = "list";
    operand = "list";
    list = [
      {
        type = "simple";
        operand = "process.path";
        data = "${pkgs.curl}/bin/curl";
      }
      {
        type = "simple";
        operand = "dest.host";
        data = "example.com";
      }
      {
        type = "simple";
        operand = "dest.port";
        data = "443";
      }
    ];
  };
};
```

Use `list` for AND rules. OpenSnitch does not support comma-separated host lists; use one `regexp` such as `^(api\.github\.com|github\.com)$` when hosts are equivalent. Prefer exact `simple` process-path matches built from package references, for example `${pkgs.openssh}/bin/ssh`; avoid generic `/nix/store/...` regexes because they are slower and broaden what can match.

## Distributed rules

Only process-agnostic baseline rules live in `modules/nixos/desktop/opensnitch.nix`. Program-specific allow rules live beside the module that enables or packages the program:

| Rule | Purpose |
| --- | --- |
| `000-allow-localhost-ipv4`, `000-allow-localhost-ipv6` in `opensnitch.nix` | Priority loopback allows for local IPC, proxies, and desktop helpers. |
| `001-reject-ld-preload-network` | Priority reject for outbound sockets from processes with path-like `LD_PRELOAD`. Breaks Flatpak apps if a user override sets `LD_PRELOAD` (e.g. missing `libdeltoid.so` on Sober → "Could not connect to server" for every HTTPS fetch). Remove with `flatpak override --user --unset-env=LD_PRELOAD org.vinegarhq.Sober` and drop the matching filesystem grant. |
| `001-reject-temp-executables` | Priority reject for binaries executed from `/tmp`, `/var/tmp`, `/dev/shm`, `/memfd`, and similar writable locations. |
| `010-allow-systemd-resolved-dns` in `modules/common/networking.nix` | Allows `${pkgs.systemd}/lib/systemd/systemd-resolved` to ports 53 and 853 (plain DNS + opportunistic DoT). FallbackDNS keeps resolution up if DoT fails. |
| `010-allow-networkmanager-lan` in `modules/common/networking.nix` | Allows `${pkgs.networkmanager}/bin/NetworkManager` only to `LAN` destinations. |
| `010-allow-systemd-timesyncd-ntp` in `modules/common/networking.nix` | Allows `${pkgs.systemd}/lib/systemd/systemd-timesyncd` NTP on port 123. |
| `020-allow-tailscaled` in `modules/nixos/terminal/tailscale.nix` | Allows the configured Tailscale daemon package; endpoints are dynamic. |
| `030-allow-librewolf-browser` in `modules/nixos/desktop/default.nix` | Allows the system LibreWolf browser binary (default browser). |
| `030-allow-brave-origin-browser` in `modules/nixos/desktop/default.nix` | Allows the flake's Brave Origin package binary when launched manually. |
| `030-allow-ssh-standard-ports` in `modules/common/base.nix` | Allows `${pkgs.openssh}/bin/ssh` to ports 22 and 443 only. |
| `040-allow-nix-known-fetch-hosts` in `modules/nixos/terminal/nix.nix` | Merges prior live Nix/Lix GitHub/cache HTTPS prompts into one exact-package rule. |
| `050-allow-vscodium-raw-githubusercontent` in `modules/nixos/desktop/vscodium/default.nix` | Allows the configured VSCodium package to fetch raw GitHub content. |
| `060-allow-lyricsctl-providers` in `modules/nixos/desktop/default.nix` | Allows the flake's `lyricsctl` wrapper to query `lrclib.net` and `api.lrc.cx` only. |
| `060-allow-open-meteo-weather` in `modules/nixos/desktop/dank-material-shell.nix` | Allows the shell weather provider `api.open-meteo.com:443`. |
| `000-allow-authenticated-root-bypass` | Allows authenticated root bypass wrapper processes. |

Live rules inspected from `/var/lib/opensnitch/rules` were migrated when they were specific enough: LibreWolf, Brave, Tailscale, SSH, NetworkManager LAN, systemd-resolved DNS/DoT, Nix/Lix GitHub/cache fetches, VSCodium raw GitHub, NTP, and DMS weather. Sloppy exact live store paths were replaced by declarative package references. The broad Orca deny rule was not migrated because it denied a whole Electron application by exact store path without destination or command context.

## Prompt review timeouts

Several networking clients use longer connect windows so you can answer OpenSnitch prompts before the client gives up:

| Component | Setting |
| --- | --- |
| Root flake Nix config | `connect-timeout = 25` seconds. |
| System Nix/Lix daemon | `connect-timeout = 25`, `stalled-download-timeout = 120`. |
| `git-sync-debug` SSH probe | `ConnectTimeout=25`, command timeout 30 seconds. |
| `models` API fetch | `curl --connect-timeout 25 --max-time 90`. |

## Authenticated bypass wrapper

`opensnitch-bypass` runs a command as root through polkit (`pkexec`) and sets `NIXCONF_OPENSNITCH_BYPASS=authenticated-root`. The priority rule `000-allow-authenticated-root-bypass` allows only processes that have both UID 0 and that environment marker.

Usage:

```bash
opensnitch-bypass -- curl https://example.com/
```

Security notes:

- This bypass intentionally requires authentication unless already root.
- The rule is broad for the authenticated root process tree. Use it for short diagnostics, not normal application launches.
- Environment matching is not a secret; UID 0 is the authentication boundary.
- Disable with:

```nix
services.opensnitch.nixconf.bypassWrapper.enable = false;
```

## Rule migration workflow

1. Let OpenSnitch prompt during normal use.
2. Inspect UI-generated rules under `/var/lib/opensnitch/rules` without starting or restarting OpenSnitch.
3. Keep only rules with a clear owner, command/path, destination, and port.
4. Merge equivalent hosts/ports into one declarative rule with a `regexp` operand.
5. Replace exact live `/nix/store/<hash>-...` paths with declarative package references such as `${pkgs.openssh}/bin/ssh`; keep process matches `simple` unless the process cannot expose a stable executable path.
6. Add the durable rule to the module that owns the program; use `modules/nixos/desktop/opensnitch.nix` only for process-agnostic baseline rules and shared schema/settings.
7. Validate with `HOST=<host> ./rebuild.sh validate`; do not run switch/rebuild actions here.

## Upstream references

- [OpenSnitch Rules wiki](https://github.com/evilsocket/opensnitch/wiki/Rules): JSON format, operators, operands, list semantics, precedence, performance, DNS best practices, localhost allow rule, and writable-location deny examples.
- [OpenSnitch Rules examples](https://github.com/evilsocket/opensnitch/wiki/Rules-examples): priority rules, process-path regexes, interpreter caution, `process.env.*` examples, and temp executable rejects.
- [OpenSnitch Configurations wiki](https://github.com/evilsocket/opensnitch/wiki/Configurations): daemon config file keys, rule path, checksum option, UI socket behavior, and GUI/default-action interaction.
- [Nix connect-timeout reference](https://nixos.org/manual/nix/stable/command-ref/conf-file#conf-connect-timeout): timeout units and behavior.
