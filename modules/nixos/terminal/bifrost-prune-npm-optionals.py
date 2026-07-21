# Drop optional package-lock entries whose os/cpu tags do not match the host.
# prefetch-npm-deps downloads every lock entry; bulk registry.npmjs.org HTTP/2
# multi-downloads fail mid-FOD with framing errors (e.g. @esbuild/openbsd-arm64).
# Env: npmOs, npmCpu (Node process.platform / process.arch tags).
# Source: modules/_pkgs/omniroute.nix (same failure class)
# Source: nixpkgs pkgs/build-support/node/prefetch-npm-deps
import json
import os
from pathlib import Path

keep_os = os.environ["npmOs"]
keep_cpu = os.environ["npmCpu"]
lock_path = Path("package-lock.json")
lock = json.loads(lock_path.read_text())
packages = lock.get("packages", {})
removed_keys = []


def host_match(meta: dict) -> bool:
    os_list = meta.get("os") or []
    cpu_list = meta.get("cpu") or []
    if not os_list and not cpu_list:
        return True
    os_ok = (not os_list) or (keep_os in os_list)
    cpu_ok = (not cpu_list) or (keep_cpu in cpu_list)
    return os_ok and cpu_ok


for key in list(packages):
    if not key:
        continue
    meta = packages[key]
    if not meta.get("optional"):
        continue
    if host_match(meta):
        continue
    del packages[key]
    removed_keys.append(key)

removed_names = {k.split("node_modules/")[-1] for k in removed_keys}
for meta in packages.values():
    opts = meta.get("optionalDependencies")
    if not isinstance(opts, dict):
        continue
    for name in list(opts):
        if name in removed_names:
            del opts[name]

lock_path.write_text(json.dumps(lock, indent=2) + "\n")
print(
    f"pruned {len(removed_keys)} non-host optional packages "
    f"(keep os={keep_os} cpu={keep_cpu})"
)
