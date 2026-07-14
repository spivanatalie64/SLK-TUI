# SLK-TUI — Interactive Kernel Configurator

A terminal user interface for building and modifying Linux kernel configs.
Works with any kernel `.config` file. No dependencies beyond `whiptail` or `dialog`.

## Features

- **Category browser** — options grouped by function (CPU, GPU, Storage, etc.)
- **Search** — find options by name or description text
- **Hardware profiles** — one-key apply config for specific machines
- **Hardware detection** — shows detected system components
- **Plain language** — every option has a human-readable description

## Usage

```bash
# On a cloned kernel tree with a .config:
slk-tui.sh

# Or point to any config:
slk-tui.sh /path/to/.config
```

## Install

```bash
git clone https://github.com/spivanatalie64/SLK-TUI.git
sudo ln -s "$PWD/SLK-TUI/bin/slk-tui.sh" /usr/local/bin/slk-tui
```

## Profiles

Built-in hardware profiles in `share/profiles/`:

| Profile | Target |
|---------|--------|
| `server-hp-dl380-g7` | HP ProLiant DL380 G7 (Xeon E5649, ES1000) |
| `server-dell-poweredge-r730` | Dell PowerEdge R730 (E5-26xx, iDRAC) |
| `server-generic` | Generic server (minimal, no GPU) |
| `laptop-generic` | Generic laptop (ACPI, WiFi, audio) |
| `desktop-generic` | Generic desktop (GPU, USB, audio) |
| `raspberry-pi-4` | Raspberry Pi 4 (BCM2711) |
| `raspberry-pi-5` | Raspberry Pi 5 (BCM2712) |
| `rockchip-rk3588` | Rockchip RK3588 (Orange Pi 5) |

## License

MIT
