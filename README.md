# Chromasurf — reTerminal CM4

<img src="assets/images/reterminal.jpg" alt="Seeed Studio reTerminal" width="480">

<sub>Image: © [Seeed Studio](https://wiki.seeedstudio.com/reTerminal/)</sub>

**Chromasurf** is an industrial IoT platform built on [Elixir](https://elixir-lang.org) and [Nerves](https://nerves-project.org), developed by [Formrausch](https://formrausch.com). It provides the firmware foundation for connected HMI terminals, gateways, and sensor nodes — with automatic network clustering, over-the-air updates, real-time messaging, and full hardware abstraction built in. Designed for production use in manufacturing, process control, and industrial automation.

This repository contains the Nerves base system image for the [Seeed Studio reTerminal](https://wiki.seeedstudio.com/reTerminal/) (CM4, aarch64). It includes the Linux kernel, bootloader, DSI display and touch drivers, and all hardware support needed to run Chromasurf applications on this device. Built on `nerves_system_br` (Buildroot) with WPE WebKit/Cog browser and GPU acceleration (Mesa V3D).

## Using

Add the system as a dependency in your Nerves app and set `MIX_TARGET=reterminal_cm4`:

```elixir
# mix.exs
{:reterminal_cm4, github: "chromasurf/reterminal_cm4", runtime: false, targets: :reterminal_cm4}
```

```bash
export MIX_TARGET=reterminal_cm4
mix deps.get
mix firmware
mix burn
```

The system ships Erlang/OTP 29 — your application needs Elixir ≥ 1.20. When using NervesKey/ATECC608A, depend on `nerves_key_pkcs11 ~> 1.3`.

## Hardware Overview

| Peripheral | Chip | Bus | Address | sysfs / Device |
|---|---|---|---|---|
| DSI display | ILI9881c | MIPI DSI | — | 720x1280, panel orientation right-up |
| Touchscreen | STM32 MCU bridge | I2C | — | `/dev/input/event*` (seeed-tp) |
| Light sensor | LTR-303ALS | I2C1 | 0x29 | `/sys/bus/iio/devices/iio:device0/` |
| Accelerometer | LIS3DHTR | I2C1 | 0x19 | IIO device |
| RTC | PCF8563W | I2C3 | 0x51 | `/dev/rtc0` |
| Crypto | ATECC608A | I2C3 | 0x60 | via NervesKey library |
| GPIO expander | PCA9554 | I2C1 | 0x38 | User buttons, LEDs, buzzer |
| Backlight | — | I2C1 | 0x45 | `/sys/class/backlight/1-0045/` |
| Battery charger | BQ24179 | I2C1 | 0x6b | (via bridge overlay) |

## Sensors

### Light Sensor (LTR-303ALS)

```elixir
# Read ambient light in lux
{lux, _} =
  File.read!("/sys/bus/iio/devices/iio:device0/in_illuminance_input")
  |> String.trim()
  |> Integer.parse()
```

### Accelerometer (LIS3DHTR)

Available as an IIO device on I2C1 at address 0x19. Use the `circuits_i2c` or IIO sysfs interface to read acceleration values.

### CPU Temperature

```elixir
{temp, _} = File.read!("/sys/class/thermal/thermal_zone0/temp") |> Integer.parse()
temp_c = temp / 1000
```

## User Interface

### LEDs

Three user LEDs controlled via sysfs:

```elixir
# Turn on LED 0
File.write("/sys/class/leds/usr_led0/brightness", "1")

# Turn off
File.write("/sys/class/leds/usr_led0/brightness", "0")

# Available: usr_led0, usr_led1, usr_led2
```

Or use the [Delux](https://hex.pm/packages/delux) library for effects:

```elixir
Delux.render(Delux.Effects.blink(:red, 2))
Delux.render(Delux.Effects.off())
```

### Buzzer

```elixir
# Beep for 100ms
File.write("/sys/class/leds/usr-buzzer/brightness", "1")
:timer.sleep(100)
File.write("/sys/class/leds/usr-buzzer/brightness", "0")
```

### Buttons

Four user buttons (btn0–btn3) via PCA9554 GPIO expander, exposed as keyboard events. Power button on GPIO 13.

## Boot

erlinit runs `/usr/sbin/boot_splash` as `pre_run_exec` and `/usr/sbin/shutdown_splash` as `run_on_exit`.
`boot_splash` starts `/usr/sbin/early_modules`, polls `/dev/fb0` every 20 ms, unbinds fbcon and
shows a picture; it returns at once and the work runs in the background. Without `/etc/splash.png` it
shows `/usr/share/chromasurf/splash.png`: the chromasurf wordmark in white on black, a red, green and blue
circle before it. `shutdown_splash` shows `/usr/share/chromasurf/shutdown.png`, the same in dark grey,
after the Erlang VM exits.

To change the pictures, put these files in the app's `rootfs_overlay`:

| File | Effect |
|---|---|
| `etc/splash.png` | boot picture, 720 × 1280 (the panel's native portrait: landscape art turned a quarter counter-clockwise), 8-bit RGB |
| `etc/shutdown.png` | shutdown picture |
| `etc/splash.d/boot` (executable) | runs after the boot picture, e.g. an animation |
| `etc/splash.d/shutdown` (executable) | runs instead of the shutdown picture |

With a custom `pre_run_exec`, call `/usr/sbin/boot_splash` from it; otherwise nerves_uevent
loads the display modules about 1.7 s after the VM starts. Measured with the monitor app: `/dev/fb0` 1.37 s after kernel start, with Linux 6.18.33 and no early module loading 6.66 s.

`early_modules` loads `vc4`, `snd-soc-hdmi-codec`, `pwm-bcm2835` and `i2c-mux-pinctrl` first, then every
device modalias except v3d: each driver that binds makes the kernel retry the deferred vc4. vc4's HDMI bind
registers a sound card and returns -EPROBE_DEFER until the hdmi-codec driver is loaded; the DSI panel binds
after it. v3d follows once `/sys/class/drm/card0` exists. vc4 and v3d otherwise register in either order, so
the panel was `card0` on some boots and `card1` on others; with the script it is `/dev/dri/card0`.

busybox here has no sub-second `sleep`; the scripts poll with `read -t 0.02` on an empty FIFO made by
`mknod`.

## Boot Files

The system's `fwup.conf` writes `config.txt`, `app.txt` and the two kernel command lines. `config.txt` ends
with `include app.txt`, and the system's `app.txt` holds only a comment. To add or override
`config.txt` lines, set `CHROMASURF_CONFIG_APP` to your own `app.txt`, as in the example below.

In the Nerves systems (`nerves_system_rpi4` and others) you copy the system's `fwup.conf` and point
`config :nerves, :firmware, fwup_conf:` at the copy. Here the system's `fwup.conf` stays in use and you set
the variables below; `app.txt` exists only in these systems.

```elixir
# config/target.exs of the app; __DIR__ is the app's config/ directory
System.put_env("CHROMASURF_CONFIG_APP", Path.expand("app.txt", __DIR__))
```

```
# config/app.txt
dtparam=ant1=on
```

The firmware reads `gpu_mem` before it follows `include`; for another `gpu_mem`, replace the
whole `config.txt`. The other variables replace a file:

```elixir
# config/target.exs of the app: config/config.txt, config/cmdline-a.txt, config/cmdline-b.txt
System.put_env("CHROMASURF_CONFIG_TXT", Path.expand("config.txt", __DIR__))
System.put_env("CHROMASURF_CMDLINE_A", Path.expand("cmdline-a.txt", __DIR__))
System.put_env("CHROMASURF_CMDLINE_B", Path.expand("cmdline-b.txt", __DIR__))
```

| Variable | Replaces | Written to |
|---|---|---|
| `CHROMASURF_CONFIG_APP` | `app.txt` | both boot partitions |
| `CHROMASURF_CONFIG_TXT` | `config.txt` | both boot partitions |
| `CHROMASURF_CMDLINE_A` | `cmdline-a.txt` | `cmdline.txt` of slot A |
| `CHROMASURF_CMDLINE_B` | `cmdline-b.txt` | `cmdline.txt` of slot B |

Start from the system's files in `~/.nerves/artifacts/reterminal_cm4-portable-<version>/images/` and keep their
`root=` partitions. Building the firmware needs fwup 1.12 or later.

## Nerves 2 and EROFS

The system builds under Nerves 1.15 and Nerves 2. It ships `images/rootfs.tar`, the kernel has
`CONFIG_EROFS_FS` and `CONFIG_SQUASHFS_ZSTD`, and the command line names no root filesystem type.

To move an app to Nerves 2:

```elixir
# mix.exs: {:nerves, "~> 2.0.0-pre.10", runtime: false}, no {:shoehorn, ...}
steps: [&Nerves.init_release/1, :assemble]

# config/target.exs, instead of `config :shoehorn, init: ..., last: ...`
config :nerves, application_sort: [init: [:nerves_runtime], last: [:nerves_pack]]

# config/config.exs: EROFS root filesystem (needs mkfs.erofs, `brew install erofs-utils`)
config :nerves, :firmware, rootfs_type: :erofs
```

On a reTerminal DM the radio app drew its first frame 3.3 s after kernel start with EROFS (lz4hc),
4.2 s with SquashFS zstd and 4.7 s with SquashFS gzip. For SquashFS zstd under Nerves 1, set
`config :nerves, :firmware, mksquashfs_flags: ["-no-xattrs", "-quiet", "-comp", "zstd", "-b", "16K"]`.

Nerves 2 expects the system archive in `~/.nerves/dl/<app>-<version>/`; a local system build puts it
in `~/.nerves/dl/`. Until a system version is released, build the app with
`NERVES_SYSTEM=~/.nerves/artifacts/reterminal_cm4-portable-<version>`.

## Reboot on Kernel Errors

The command line carries `oops=panic` and `sysctl.kernel.panic_on_rcu_stall=1`: an oops or an RCU stall
panics the kernel, and the watchdog restarts the device. To switch the reboot off at runtime:

```elixir
File.write!("/proc/sys/kernel/panic_on_oops", "0")
File.write!("/proc/sys/kernel/panic_on_rcu_stall", "0")
```

or at build time with `CHROMASURF_CMDLINE_A` / `CHROMASURF_CMDLINE_B` pointing at command lines without
both parameters.

## Crash Logging (pstore)

`config.txt` loads `ramoops-pi4` with 128 KiB: the kernel console (32 KiB), panic dumps (16 KiB records)
and pmsg (32 KiB) survive a watchdog reset or a warm reboot in `/sys/fs/pstore`.

## GPU Memory

`config.txt` sets `gpu_mem=76`, the Raspberry Pi OS default on the Pi 4. vc4 (KMS) and v3d, which WebKit and
emerge render with, allocate from the 512 MB CMA area of `vc4-kms-v3d,cma-512`, not from `gpu_mem`.
`gpu_mem` is the VideoCore firmware's share: H.264 decode and encode through `bcm2835-codec`
(`/dev/video10`, `/dev/video11`), the camera ISP (`bcm2835-isp`, libcamera) and MMAL. 76 MB ran CarPlay's
H.264 stream on a reTerminal DM.

Raise it when the firmware reports out of memory (`vcsm`/`mmal` errors in `dmesg`, a codec or camera that
fails to open), for example with several decode streams or the legacy camera stack at full sensor
resolution. Below 32 MB the firmware loads the cut-down `start4cd.elf` without codecs. The firmware reads
`gpu_mem` before it follows `include app.txt`, so to change it, replace `config.txt`
(`CHROMASURF_CONFIG_TXT`, see [Boot Files](#boot-files)). Every MB above 76 is taken from Linux.

## Display

### DSI Configuration

The 720x1280 DSI display is portrait; its panel orientation is right-up. Kernel cmdline includes `video=DSI-1:720x1280@60`. HDMI output is disabled by default: `vc4.force_hotplug=1` reports
HDMI-A-1 as connected even without a monitor, and Cog selects the first connected connector, so
`video=HDMI-A-1:d` in the kernel command line switches it off.
`File.write("/sys/class/drm/card0-HDMI-A-1/status", "detect")` switches it back on.

### Rotation and Touch

The panel scans out 720 × 1280 in portrait. vc4 rotates planes by 0° and 180° only, so the program
that draws turns the picture to landscape in its own GPU pass. The connector's panel orientation is
right-up; fbcon and Weston read it, Cog and Emerge do not. With it alone fbcon rotates by 270° in
software, and the primary plane's rotation property stays 0. A `rotate=` in `video=…` adds to the
orientation; at a sum of 180° fbdev sets the plane's rotation property, and it stays set for the next DRM
master.

The panel MCU reports touch through the `seeed-tp` driver (`mipi-dsi` package). With `tp_rotate=1` in
`config.txt` its coordinates match the framebuffer. The axis range is 1280 × 720; libinput and Emerge scale it to the panel.

| Program | Picture | Touch |
|---|---|---|
| Cog | `COG_PLATFORM_PARAMS=renderer=gles,rotation=3` in `/etc/erlinit.config` | Matrix in `/etc/udev/rules.d/99-touchscreen.rules` |
| Emerge | `rotation: 270` in `Emerge.Config.DRM` (chromasurf/emerge), or `Emerge.UI.rotate(90)` on a 1280 × 720 element | Framebuffer coordinates, nothing to set |

`cog <url>` starts in landscape without `--platform` and `--platform-params`; Cog reads
`COG_PLATFORM_NAME` and `COG_PLATFORM_PARAMS` when they are missing. Cog does not rotate touch, so
libinput gets a calibration matrix from the udev database. `boot_splash` starts `udevd`, which writes the
database.

For another Cog rotation, pass `--platform-params=renderer=gles,rotation=<n>` and write a rule to
`/run/udev/rules.d` whose file name sorts after `99-touchscreen.rules`. udev skips a file in `/run` with
the same name as one in `/etc`; of two rules, the later one sets the matrix.

| `rotation` | `LIBINPUT_CALIBRATION_MATRIX` |
|---|---|
| 0 | `1 0 0 0 1 0` |
| 1 | `0 -1 1 1 0 0` |
| 2 | `-1 0 1 0 -1 1` |
| 3 | `0 1 0 -1 0 1` |

```elixir
File.mkdir_p!("/run/udev/rules.d")

File.write!("/run/udev/rules.d/99-zz-touch-rotation.rules", """
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="seeed-tp", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
""")

System.cmd("udevadm", ["control", "--reload"])
System.cmd("udevadm", ["trigger", "--subsystem-match=input", "--action=change"])
System.cmd("udevadm", ["settle", "--timeout=5"])
```

### Backlight

```elixir
# Set brightness (0–255)
File.write("/sys/class/backlight/1-0045/brightness", "128")

# Read current brightness
File.read!("/sys/class/backlight/1-0045/brightness")
```

### Kiosk Mode (Cog on DRM)

Cog draws directly on the panel; `examples/kiosk_drm.ex` is a supervisor setup. `/etc/erlinit.config` sets
`COG_PLATFORM_NAME`, `COG_PLATFORM_PARAMS` and `XDG_RUNTIME_DIR=/run`, and HDMI is off, so Cog starts
with only a URL:

```elixir
:os.cmd(~c"cog http://localhost:4000")
```

### Kiosk Mode (Weston + Cog)

The system includes Weston compositor and Cog WebKit browser for kiosk applications. See `examples/kiosk.ex` for a full supervisor setup. Weston turns touch with its output transform (`weston.ini`), so before starting it set the identity matrix `1 0 0 0 1 0` with a rule as in "Rotation and Touch". Touch under Weston is not tested with the touch coordinates of v1.3.0. Quick start:

```elixir
# Start Weston
:os.cmd(~c"seatd &")
:os.cmd(~c"XDG_RUNTIME_DIR=/run weston -B drm &")

# Open a URL in fullscreen
:os.cmd(~c"XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-1 cog http://localhost:4000")
```

Remote WebKit Inspector is available on port 9222 when `WEBKIT_INSPECTOR_HTTP_SERVER=0.0.0.0:9222` is set.

### Rendering Performance

The system ships with four performance defaults; apps do not need to configure anything:

- **GPU painting**: `/etc/erlinit.config` sets `WEBKIT_SKIA_GPU_PAINTING_THREADS=4`, so
  WPE WebKit's Skia rasterizes on the v3d GPU instead of the CPU — roughly twice the
  frame rate when scrolling image-heavy pages. Override per launch via the `env:`
  option of the process that starts Cog.
- **CPU governor**: the kernel defaults to `performance`; `schedutil` costs frame
  deadlines under scroll load.
- **Transparent Hugepages**: enabled, which lets the v3d driver use Super Pages.
- **Malloc arenas**: `/etc/erlinit.config` sets `MALLOC_ARENA_MAX=2` for the BEAM and the
  programs it starts. With glibc's default of up to 32 arenas, a BEAM with the Emerge
  renderer settled at 380 MB RSS in a soak test instead of 190 MB.

Known limitation: content with `box-shadow` on scrolling surfaces stalls WPE 2.50's
rendering pipeline regardless of these settings — avoid soft shadows in kiosk UIs.

## Security

### ATECC608A

Microchip crypto co-processor at I2C3 address 0x60. Use [NervesKey](https://hex.pm/packages/nerves_key) for provisioning and certificate management:

```elixir
{:ok, i2c} = ATECC508A.Transport.I2C.init([])
info = NervesKey.default_info(i2c)
serial = info.manufacturer_sn
```

Note: The ATECC608A is in sleep mode by default and won't appear in `i2cdetect` without a wake sequence.

## RTC

NXP PCF8563W at I2C3 address 0x51. Available as `/dev/rtc0`:

```elixir
# Read hardware clock
:os.cmd(~c"hwclock -r")

# Set system time from RTC
:os.cmd(~c"hwclock -s")
```

## Camera

Supports official Raspberry Pi camera modules via [`libcamera`](https://libcamera.org/):

```elixir
cmd("libcamera-jpeg -n -v -o /data/test.jpeg")
```

## Audio

Audio output via WM8960 codec (bridge overlay) or HDMI. Linux ALSA drivers:

```elixir
# Force HDMI output
cmd("amixer cset numid=3 2")

# Force analog jack output
cmd("amixer cset numid=3 1")
```

## Supported WiFi Devices

The onboard Raspberry Pi CM4 WiFi module (`brcmfmac` driver) is included and enabled.

## Provisioning

Key-value store outside any filesystem for device identity:

```elixir
# Set serial number (persists across firmware updates)
cmd("fw_setenv nerves_serial_number 12345678")

# Or at burn time:
# NERVES_SERIAL_NUMBER=12345678 fwup firmware.fw
```

## Building the System

Prebuilt artifacts are published as GitHub releases. To build from source:

```bash
mix deps.get
mix compile
mix nerves.artifact
```

WebKit compilation is slow and memory-hungry. If the build gets OOM-killed, simply run `mix compile` again — Buildroot resumes where it left off.

## Linux Kernel

Kernel: Linux 6.18.50 (Raspberry Pi fork, tag `stable_20260911`)
Config: `linux-6.18.defconfig` (stripped-down for Nerves)
Custom patches: `linux/ili9881c_fix.patch` (DSI display driver fix)

---

<img src="assets/images/fr_io_logo_signet_red.svg" alt="formrausch logo" height="24" align="top"> [formrausch](https://formrausch.com) /ˈfɔʁmˌʁaʊ̯ʃ/ is a creative studio uniting designers and developers to build beautiful, functional digital products.

## License

Apache-2.0
