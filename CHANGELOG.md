# Changelog

This project does NOT follow semantic versioning. The version increases as
follows:

1. Major version updates are breaking updates to the build infrastructure.
   These should be very rare.
2. Minor version updates are made for every major Buildroot release. This
   may also include Erlang/OTP and Linux kernel updates. These are made four
   times a year shortly after the Buildroot releases.
3. Patch version updates are made for Buildroot minor releases, Erlang/OTP
   releases, and Linux kernel updates. They're also made to fix bugs and add
   features to the build infrastructure.

## v1.3.0

Moves to Buildroot 2026.08.1, Erlang/OTP 29.1.2 and Linux 6.18.50, brings the
boot-time changes measured on the reTerminal DM into the system, and runs under
Nerves 1 and Nerves 2.

* Package updates
  * [nerves_system_br 1.35.3](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.35.3):
    Buildroot 2026.08.1, Erlang/OTP 29.1.2, fwup 1.17.0. Fixes the missing
    available-memory patch on OTP 29 (`system_memory_high_watermark`).
  * Linux 6.18.50 (`raspberrypi/linux` `stable_20260911`), rpi-firmware 1.20260915
    `linux/ili9881c_fix.patch` follows the new `rzw,t101p136cq` entry in the
    panel match table.
  * Target toolchain: the Nerves toolchain 15.3.0 (GCC 15.3, glibc 2.43)
    instead of the Arm GNU Toolchain 15.2 (glibc 2.42). Apps compile their NIFs
    with the same toolchain the system is built with.

* Changes
  * `cmdline-a.txt` / `cmdline-b.txt`: `loglevel=4` instead of 7. On the
    reTerminal DM the serial console at 115200 baud replayed the full kernel
    log; root mounted at 0.78 s instead of 2.23 s, `/dev/fb0` appeared at
    1.61 s instead of 3.51 s.
  * `cmdline-a.txt` / `cmdline-b.txt`: no `rootfstype=squashfs`, so the same
    system boots SquashFS and EROFS root filesystems.
  * `kernel8.img` is the gzip-compressed kernel (13.6 MB → 5.9 MB, 0.75 s less
    before the kernel starts on the DM). `post-createfs.sh` writes
    `images/kernel8.img.gz`; `images/Image` stays in the artifact.
  * `config.txt`: `kernel=` and `device_tree=` named explicitly,
    `hdmi_ignore_hotplug:1=1`.
  * `config.txt`: drop `disable-bt` / `disable-wifi` (their `.dtbo` files were
    never on the boot partition).
  * `config.txt`: drop `tpm-spi-slx9670`. The reTerminal has no TPM (its secure
    element is the ATECC608A on i2c3); the probe on spi0.0 timed out with -110
    2.65 s into the boot. The overlay is no longer built or written.
  * `config.txt`: `dtparam=pcie=off`. Nothing is connected to the CM4's PCIe
    lane on the reTerminal; `brcm-pcie` waited 343 ms for a link before init
    (root 0.77 → 0.42 s). A project with a PCIe device on the E10-1 sets
    `dtparam=pcie=on` in its own `config.txt`.
  * `early_modules` loads `snd-soc-hdmi-codec` together with `vc4`. vc4's
    HDMI bind registers a sound card and defers until the codec driver is
    there; the DSI panel deferred with it about 50 times. fb0 on the reTerminal
    2.55 → 1.68 s after kernel start.
  * `mipi_dsi`: no retries when the panel MCU answers 0x43. After a warm reboot
    it answered 0x43 through all three retries and the driver went on anyway;
    the probe lost 300 ms.
  * Only `bcm2711-rpi-cm4.dtb` is built and written; the Pi 4B and Pi 400
    device trees are gone.
  * fwup: boot partition files are written as deltas against the other slot on
    upgrade (`require-fwup-version` 1.12.0).
  * fwup: an app replaces `config.txt`, `cmdline-a.txt` or `cmdline-b.txt` by
    setting `CHROMASURF_CONFIG_TXT`, `CHROMASURF_CMDLINE_A` or
    `CHROMASURF_CMDLINE_B` to a file path in the environment of `mix firmware`;
    it no longer needs its own copy of `fwup.conf`.
  * `fwup.conf` is rendered from `fwup.conf.eex` before every `mix compile`;
    the checksum covers only the template and now also the `linux/` patches.
  * Kernel: `CONFIG_SQUASHFS_ZSTD=y` and `CONFIG_EROFS_FS=y`. Apps can switch to
    `-comp zstd` (Nerves 1, `mksquashfs_flags`) or `rootfs_type: :erofs`
    (Nerves 2).
  * `config/config.exs` starts `nerves_bootstrap` and `cli/0` sets
    `default_target: :target`, replacing the `loadconfig` alias (as in
    `nerves_system_rpi4`). `mix docs` works with parallel dependency
    compilation (`MIX_OS_DEPS_COMPILE_PARTITION_COUNT`).
  * Nerves 2: `rootfs.tar` is built again (Nerves 2 assembles the root
    filesystem from it), `nerves` allows `~> 2.0`, toolchain package 15.3.1.
  * `rootfs_overlay/usr/sbin/early_modules`, run as erlinit `--pre-run-exec`:
    loads kernel modules before the Erlang VM starts, the display path first and
    v3d after vc4. On a reTerminal DM vc4 is ready at 2.97 s instead of 5.03 s,
    v3d at 3.04 s, `/dev/fb0` at 3.38 s instead of 5.31 s, and the panel is
    `/dev/dri/card0` on every boot. Not yet measured on a reTerminal. See
    README, "Boot".

## v1.2.6

Takes the kernel log off the panel, and drops the `nerves_container` add-on now
that Nerves ships the Apple `container` build runner itself.

* Changes
  * `cmdline-a.txt` / `cmdline-b.txt`: drop `console=tty3`. v1.2.3 raised
    `loglevel` from 0 to 7 on the assumption that a kernel console on `tty3`
    never reaches the display. It does: `console=tty3` registers a VT console,
    and fbcon paints that VT onto the framebuffer, so the boot messages stood on
    the panel until Cog claimed DRM master. Without it the kernel talks to
    `serial0` only — which is where v1.2.3 wanted those logs read anyway, and
    the full `loglevel=7` stream is still there.
  * `mix.exs`: require `{:nerves, "~> 1.15"}` and drop both the
    `nerves_container` dependency and the explicit `build_runner:` selection.
    Nerves 1.15.0 ships the Apple `container` build runner upstream (the same
    code) and selects it on Apple Silicon by itself, falling back to Docker
    elsewhere. Build volumes carry over unchanged — same names, same
    `.container_id`, same `/home/nerves/project` working directory — so this
    costs no rebuild.

## v1.2.5

Fixes the web process crash around cross-site navigations:

    wl_display#1: error 0: invalid object 12
    (WPEWebProcess:497): WPE-FDO-ERROR **: Failed to bind wl_compositor

WPEBackend-fdo offers `zwp_linux_dmabuf_v1` at version 4 but implements
`get_surface_feedback` as an empty stub, so no server-side resource exists for
the id the client allocated. Mesa 25.2 and newer use per-surface feedback and
destroy that object when a surface goes away, which makes libwayland-server post
`wl_display.error(invalid object)` — fatal for the whole connection, not just the
object. The next view target on that connection binds no `wl_compositor` and
aborts the web process.

* Changes
  * `patches/wpebackend-fdo/0001-linux-dmabuf-implement-per-surface-feedback.patch`:
    answer per-surface feedback with the default feedback's tranches. The
    protocol allows it — per-surface feedback is an optimisation hint.
  * `nerves_defconfig`: `BR2_GLOBAL_PATCH_DIR` gained
    `$(NERVES_DEFCONFIG_DIR)/patches` so this system can carry patches of its own.
  * `mix.exs`: added `patches` to `package_files/0`, so patch-only changes
    invalidate the artifact checksum. Note that `package` and `external.mk` are
    still missing there — out-of-tree kernel module changes do not bump the
    checksum today.

See `docs/wpe-fdo-surface-feedback-crash.md` in the monorepo for the protocol
trace. The bug is still present upstream on WPEBackend-fdo `main`.

## v1.2.4

Makes the browser fast by default — the same three changes as reterminal_dm_cm4
v1.2.5, ported over. Profiled on the reTerminal DM (same SoC): image-heavy
pages ran at ~30 fps with the CPU rasterizing and the GPU idle; with these
defaults the same pages hold ~60 fps (p50 frame time 17 ms) and touch flicks
feel fluid.

* Changes
  * `rootfs_overlay/etc/erlinit.config`: set `WEBKIT_SKIA_GPU_PAINTING_THREADS=4`
    system-wide. Without it, WPE WebKit 2.50's Skia paints on the CPU with
    `nCores/2` worker threads while the v3d GPU idles. Every app that launches
    Cog inherits the variable through the BEAM's environment and can still
    override it per launch. Note for apps that set their own
    `config :nerves, :erlinit` overrides: Nerves merges against the system
    *source* in `deps/`, so those apps pick this default up once they depend on
    this release.
  * `linux-6.18.defconfig`: default the cpufreq governor to `performance`
    (`CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE`). `schedutil` idles at 600 MHz
    and oscillates between 1.3 and 2.0 GHz under scroll load; measured p50
    frame time was 27 ms vs 17 ms with `performance`. Kiosks on mains power
    have no reason to save that energy; `schedutil` remains available at
    runtime via sysfs.
  * `linux-6.18.defconfig`: enable `CONFIG_TRANSPARENT_HUGEPAGE`, which the v3d
    driver uses for Super Pages (fewer GPU-MMU TLB misses on large textures).
    The boot log's "Transparent Hugepage support is recommended" warning turns
    into "Using Transparent Hugepages".
  * `README.md`: new "Rendering Performance" section documenting the three
    defaults and a known WPE 2.50 limitation (`box-shadow` on scrolling content
    stalls the rendering pipeline regardless of settings — analysis in the
    chromasurf monorepo under `docs/wpe-box-shadow-raf-stall.md`).
    `examples/kiosk_drm.ex` notes that GPU painting needs no per-app env entry.

## v1.2.3

Makes a firmware that fails to boot say so, plus the Cog-on-DRM kiosk example
that had been sitting unreleased since v1.2.2.

* Changes
  * `rootfs_overlay/etc/erlinit.config`: send the IEx prompt to `ttyS0` instead
    of `tty1`. On a kiosk Cog owns the DRM device, so a prompt on `tty1` cannot
    be reached — and since everything the VM writes follows this setting, crash
    reports went there too. A firmware that died during boot was
    indistinguishable from one with a black screen. The headless sibling
    (`recomputer_r100x_cm4`) has always been on `ttyS0`; a display Cog has taken
    over is no more reachable than no display at all. `-s /usr/bin/nbtty` now
    also matches what its own comment says it is for. Downstream can put it back
    with `config :nerves, :erlinit, ctty: "tty1"`.
  * `cmdline-a.txt` / `cmdline-b.txt`: `loglevel=0` → `loglevel=7`. At 0 even a
    kernel failure during early boot is silent, before Erlang starts and
    `nerves_logging`'s kmsg tailer can pick anything up. The kernel console is on
    `tty3`, so this does not reach the panel and the kiosk stays clean.
  * `examples/kiosk_drm.ex`: the Cog-on-DRM kiosk pipeline, documented as an
    example — merged after v1.2.2 but never released.

Both console changes were found while bringing up `myelin_demo` on the DM
variant, where a broken release stayed invisible for a day because the console
pointed at a display the browser had taken over. The same fix ships there as
v1.2.4.

## v1.2.2

Build tooling — no functional changes to the image.

* Changes
  * macOS builds can now run in an Apple `container` Linux VM (no Docker or
    remote build server needed) via
    [nerves_container](https://github.com/chromasurf/nerves_container) — it is
    auto-selected on Apple Silicon and falls back to Docker otherwise. Upstream
    support is proposed in nerves-project/nerves#1190.

## v1.2.1

Documentation-only update — no functional changes to the image.

* Changes
  * README: add a device photo, correct the kernel documentation (Linux 6.18,
    `linux-6.18.defconfig`), document the OTP 29 / Elixir 1.20+ requirement,
    and clarify that an OOM-killed build resumes by re-running `mix compile`.

## v1.2.0

Minor update for a major Buildroot release: tracks `nerves_system_br` v1.34.0
and `kiosk_system_rpi4` v2.1.0, bringing a new Erlang/OTP, Linux kernel, and
toolchain.

**Breaking for downstream:** the image now ships Erlang/OTP 29, so consuming
projects must build with OTP 29 (Elixir 1.20+). Devices using a NervesKey /
ATECC608 must update `nerves_key_pkcs11` to `~> 1.3` to avoid a TLS segfault.

* Changes
  * Use Liberation fonts as the default sans-serif/serif/monospace families
    (fontconfig aliases, from `kiosk_system_rpi4` v2.1.0) — fixes rendering
    issues in WebKit.
  * Remove the `pigpio` package — dropped upstream in Buildroot 2026.05 (no
    longer maintained). Use `libgpiod` / `circuits_gpio` for GPIO.

* Updated dependencies
  * [nerves_system_br v1.34.0](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.34.0)
    (Erlang/OTP 29.0.2, Buildroot 2026.05, GCC 15.3.0)
  * Linux kernel 6.18 (Raspberry Pi `stable_20260527` tag), RPi firmware 1.20260521

## v1.1.4

Security/bug fix update that tracks `nerves_system_br` v1.33.9 (up from
v1.33.4) and pulls in the relevant `kiosk_system_rpi4` v2.0.x refinements.

* Changes
  * Switch the runtime cgroup hierarchy to cgroup v2 — kernel config (PSI,
    CFS bandwidth) plus an `erlinit` `cgroup2` mount — and re-enable the memory
    controller with `cgroup_enable=memory cgroup_memory=1` on the kernel command
    line.
  * Trim unused Weston shells (fullscreen, IVI, screenshare) and the GStreamer
    WPE plugin to shrink the image; only the kiosk shell is used.
  * Enable `shared-mime-info` for WebKit web inspector support.

* Updated dependencies
  * [nerves_system_br v1.33.9](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.33.9)
    (Erlang/OTP 28.5.0.1, Buildroot 2025.11.3, fwup 1.16.0, glibc 2.43
    compatibility fix, Raspberry Pi WiFi roaming patch)

## Earlier releases

Detailed notes for v1.1.3 and earlier live in the
[GitHub releases](https://github.com/chromasurf/reterminal-cm4/releases):
v1.1.3, v1.1.2, v1.1.1, v1.1.0, v1.0.1, v1.0.0.
