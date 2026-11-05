# fastflowlm

FastFlowLM (`flm`): LLM runtime for the AMD Ryzen AI NPU (XDNA2, Ryzen AI 300
series), together with the XRT runtime and the `amdxdna` userspace plugin it
needs. Exposed as `per.fastflowlm`.

Derived from `github:noamsto/nix-amd-ai` (packaging only, reviewed and reduced).
Nothing here is downloaded at build time except `fetchFromGitHub` sources.

## Layout

```
pkgs/fastflowlm/
  package.nix                 flm itself; builds xrt + plugin + combined internally
  Cargo.lock                  vendored crates for third_party/tokenizers-cpp (crates.io, checksummed)
  patches/use-system-codecs.patch   the only patch kept (no network during the build)
  xrt/                        Xilinx/XRT build, 2 small CMake patches
  xrt-plugin-amdxdna/         amd/xdna-driver userspace shim
  xrt-combined/               symlinkJoin: plugin must sit next to libxrt_coreutil
```

Only `fastflowlm` is exposed. XRT and the plugin are internal on purpose: the
flake calls every `pkgs/<name>/package.nix` with plain `pkgs.callPackage`
(siblings cannot see each other) and the overlay would otherwise shadow
nixpkgs' `xrt` system-wide. They are reachable as passthru:
`per.fastflowlm.xrt-combined`, `.xrt`, `.xrt-plugin-amdxdna`.

## What you are trusting

| Part | Origin | Open? | Pinned by |
| --- | --- | --- | --- |
| XRT | `Xilinx/XRT` (AMD) | source | commit + hash |
| amdxdna plugin | `amd/xdna-driver` (AMD) | source | commit + hash |
| flm CLI / server | `ROCm/FastFlowLM` (AMD's ROCm org) | MIT source | tag + hash |
| `src/lib/xrt/*.so` engine libraries | same repo, inside the tag | **closed** | same hash |
| `.xclbin` NPU kernels | same repo, inside the tag | **closed** | same hash |
| Rust crates (78) | crates.io | source | `Cargo.lock` checksums |
| Model weights/kernels | HuggingFace, downloaded by `flm pull` at runtime | **closed** | not pinned by Nix |

The closed parts come from the upstream repository itself, not from this
repo: nothing binary is committed here. `meta.sourceProvenance` declares
`binaryNativeCode` and `binaryFirmware`, `meta.license` includes `unfree`.
Read `LICENSE_BINARY.txt` in the upstream tree for the exact terms of the
closed parts: redistribution is allowed only unmodified, and the binaries come
with no warranty. The source itself is under `LICENSE_RUNTIME.txt` (MIT).

Runtime note: `flm pull <model>` needs network access (HuggingFace). Running
an already pulled model should not.

## Patches: what was dropped and why

The original flake carries 24 patches (~3000 lines of C++) to `flm serve`
(request validation, cancellation, race conditions). They were only
keyword-scanned for network/exec calls, not reviewed line by line. This
package keeps just `use-system-codecs.patch` (CMake only, needed because the
sandbox cannot download codec tarballs). If `flm serve` misbehaves (crashes on
malformed requests, leaks connection slots, ignores client disconnects),
re-add individual patches from the original repo one at a time, after reading
each one.

## Updating (manual, on purpose)

Do not let automation bump this package: a new version means new closed
binaries, and `Cargo.lock` is not upstream (it is injected), so an automatic
bump can build a mismatched tree.

1. Read the upstream release notes and the `LICENSE_BINARY.txt` diff.
2. Bump `version` and `hash` in `package.nix`
   (`nix run nixpkgs#nix-prefetch-github -- --fetch-submodules ROCm FastFlowLM --rev vX.Y.Z`).
3. Regenerate `Cargo.lock` from the new `third_party/tokenizers-cpp/rust`
   (keep every registry entry checksummed; no `git+` sources).
4. Check `patches/use-system-codecs.patch` still applies.
5. If the XRT / plugin pins must move, keep XRT on the commit that the
   `amd/xdna-driver` commit references as its submodule.
6. Rebuild, then repeat the audit (blob inventory with sha256, embedded URLs
   in `flm` and the `.so` files, RPATHs) and the hardware test (`flm validate`,
   `flm pull`, a short run inside `unshare -rn`).

## NixOS side (reference, lives in the system config, not here)

```nix
{ config, lib, pkgs, per, ... }:
let
  flm = per.fastflowlm;
in {
  assertions = [
    {
      assertion = lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.14";
      message = "amdxdna (AMD NPU) needs Linux >= 6.14.";
    }
    {
      assertion = !(builtins.any (p: builtins.elem p ["amd_iommu=off" "iommu=off"]) config.boot.kernelParams);
      message = "amdxdna needs the IOMMU (PASID/SVA): do not disable it.";
    }
  ];

  boot.kernelModules = ["amdxdna"];
  hardware.enableRedistributableFirmware = true; # NPU firmware ships in linux-firmware
  environment.systemPackages = [flm];

  # NPU buffers are pinned memory.
  security.pam.loginLimits = [
    { domain = "@video";  type = "-"; item = "memlock"; value = "unlimited"; }
    { domain = "@render"; type = "-"; item = "memlock"; value = "unlimited"; }
  ];

  # Your user needs the group that owns /dev/accel/accel0 (video and/or render).
  # users.users.<you>.extraGroups = ["video" "render"];

  # Only if /dev/accel/accel0 is NOT already group-accessible (check first):
  # services.udev.extraRules = ''
  #   SUBSYSTEM=="accel", DRIVERS=="amdxdna", GROUP="video", MODE="0660"
  # '';
}
```

### Optional: hardened server, loopback only

Verify the real flags with `flm serve --help` first. Pull models beforehand
as the service user (`sudo -u flm flm pull <model>`), since the service itself
has no outbound network.

```nix
users.users.flm = {
  isSystemUser = true;
  group = "flm";
  extraGroups = ["video" "render"];
  home = "/var/lib/flm";
};
users.groups.flm = {};

systemd.services.flm = {
  description = "FastFlowLM server (AMD NPU)";
  # Start on demand: `systemctl start flm`. Add wantedBy only once it is proven.
  serviceConfig = {
    User = "flm";
    Group = "flm";
    ExecStart = "${lib.getExe flm} serve"; # VERIFY: flags, port (default 52625)
    Environment = ["HOME=/var/lib/flm"];
    StateDirectory = "flm";
    LimitMEMLOCK = "infinity";

    # The service can reach only the NPU device and loopback.
    DevicePolicy = "closed";
    DeviceAllow = ["/dev/accel/accel0 rw"]; # VERIFY the device node
    IPAddressDeny = "any";
    IPAddressAllow = ["localhost"];
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];

    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
};
```

`IPAddressDeny = "any"` blocks every address except the allowed ones, so the
server answers only on loopback even if it binds to `0.0.0.0`. (Do not use
`PrivateNetwork = true` for a server: the host could not reach it.)
If the unit fails, read `journalctl -u flm` and relax one option at a time;
`systemd-analyze security flm` scores the result.
