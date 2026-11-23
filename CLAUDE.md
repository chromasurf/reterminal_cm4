# CLAUDE.md

Nerves system `:reterminal_cm4` for the Seeed reTerminal (CM4, aarch64), repo `chromasurf/reterminal_cm4`.
Build, release and the shared CM4 stack are described in the monorepo's `CLAUDE.md` (`../../CLAUDE.md`).

## Stack

- `nerves_system_br` 1.35.3: Buildroot 2026.08.1, Erlang/OTP 29, fwup 1.17
- Linux 6.18.50 (`raspberrypi/linux` `stable_20260911`), rpi-firmware 1.20260915
- Nerves toolchain 15.3 (GCC 15.3, glibc 2.43)
- WPE WebKit and Cog on DRM, Mesa v3d, Weston
- Builds under Nerves 1.15 and Nerves 2 (`rootfs.tar`, `CONFIG_EROFS_FS`, `CONFIG_SQUASHFS_ZSTD`)

## Build

```bash
mix deps.get
mix compile               # full Buildroot build in the Apple container VM
mix generate_fwup_conf    # renders fwup.conf from fwup.conf.eex; mix compile runs it too
```

- The host toolchain comes from `.tool-versions`; outside a mise shell use `mise exec -- mix …`.
- The artifact checksum covers the files in `source_finger_print_files/0` in `mix.exs`, README and CHANGELOG
  included. Any change there produces a new artifact.
- `mix nerves_system_linter` starts a full build.
- After changing or removing a file in `patches/`, delete the build volumes. An incremental build does not
  extract the package again.

## Files

| File | Content |
|---|---|
| `nerves_defconfig` | Buildroot packages, toolchain, kernel source |
| `linux-6.18.defconfig` | Kernel config; governor `performance`, THP, pstore, EROFS |
| `linux/ili9881c_fix.patch` | Panel patch, rebased for every kernel bump |
| `patches/wpebackend-fdo/` | Buildroot package patch (`BR2_GLOBAL_PATCH_DIR`) |
| `config.txt` | Boot config, overclocked; ends with `include app.txt` |
| `app.txt` | Empty except for a comment; the app replaces it via `CHROMASURF_CONFIG_APP` |
| `cmdline-a.txt`, `cmdline-b.txt` | `root=/dev/mmcblk0p5` / `p6`, `loglevel=4`, `oops=panic` |
| `fwup.conf.eex` | A/B with tryboot; boot files as deltas against the other slot |
| `fwup_include/fwup-common.conf` | Partition layout; `APP_PART_OFFSET` stays fixed for OTA from v1.x |
| `fwup-ops.conf` | factory-reset, revert, validate, status |
| `post-createfs.sh` | Writes `images/kernel8.img.gz`, the gzip kernel |
| `ramoops-pi4-overlay.dts` | pstore overlay, 128 KiB |
| `rootfs_overlay/etc/erlinit.config` | Console `ttyS0`, `WEBKIT_SKIA_GPU_PAINTING_THREADS=4`, `COG_PLATFORM_NAME`/`COG_PLATFORM_PARAMS` (rotation=3), `XDG_RUNTIME_DIR=/run`, splash hooks |
| `rootfs_overlay/etc/udev/rules.d/99-touchscreen.rules` | `seeed-tp` touch matrix for Cog rotation=3 |
| `rootfs_overlay/usr/sbin/` | `boot_splash`, `early_modules`, `shutdown_splash` |
| `rootfs_overlay/usr/share/chromasurf/` | Default boot and shutdown pictures, 720 × 1280 |
| `examples/` | App code for reference, not part of the system |

`gpu_mem` takes effect only in `config.txt`; the firmware reads it before `include app.txt`.

## Boot

erlinit runs `/usr/sbin/boot_splash` as `pre_run_exec`. It starts `early_modules` (vc4 and
`snd-soc-hdmi-codec` first, v3d once `/sys/class/drm/card0` exists) and shows `/etc/splash.png`, or
`/usr/share/chromasurf/splash.png` without it, once `/dev/fb0` exists. It starts `udevd` in the background;
libinput reads the touch matrix from its database. `shutdown_splash` runs as `run_on_exit`.

Touch and framebuffer share panel coordinates (portrait). Cog rotates the picture and gets the touch rotation
from the udev matrix; Emerge apps rotate their content themselves (README, "Rotation and Touch").

## Packages (`package/`)

| Package | Purpose |
|---|---|
| `rethings` | Seeed device tree overlays (`reTerminal`) |
| `mipi-dsi` | Panel MCU driver for the DSI display and `seeed-tp` touch; reads the `touchscreen-*` DT properties |
| `ltr30x` | Light sensor LTR-303ALS |
| `lis3lv02d` | Accelerometer |
| `bq24179_charger` | Battery charger |
| `rtc-pcf8563w` | RTC |
