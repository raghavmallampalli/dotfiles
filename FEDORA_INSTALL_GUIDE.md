# Fedora install guide

Fedora (regular, not atomic) with niri + DankMaterialShell, set up by this repo's scripts. Works for a
fresh disk or for reinstalling while keeping an existing `/home`.

**You need:**
- A USB stick (e.g. Ventoy) with **Fedora Everything netinstall (x86_64)**, from
  https://fedoraproject.org/everything/download. Add **GParted Live** if you need to resize partitions.
- **Internet during the install**: the netinstall downloads packages. Ethernet is easiest.
- **Secure Boot off** in the firmware if you want hibernation (Fedora blocks it under Secure Boot).

---

## 1. Partitions

Target layout:

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| EFI | 1 GB | vfat | `/boot/efi` (reuse an existing one; **don't format it** if another OS boots from it) |
| Swap | ≥ RAM | swap | needed for hibernation |
| Boot | 2 GB | ext4 | `/boot` |
| Root | 60 GB+ | btrfs, subvolume `root` | `/` |
| Home | rest | btrfs (or keep an existing one) | `/home`, attached after the install (step 3) |

To make room on a disk that already has an OS, boot **GParted Live**, shrink that partition from the
end ("Free space following"), **Apply**, and leave the space unallocated. Back up first.

## 2. Installer

Boot the USB → **Fedora Everything netinstall**. On the **Installation Summary**:

- **Time & Date:** your time zone, Network Time on.
- **Network & Host Name:** connect, and set a host name.
- **Software Selection:** **Minimal Install**, no add-ons. The scripts install the desktop.
- **Installation Destination** → the disk → **Advanced Custom (Blivet-GUI)** → Done:
  - EFI partition → Edit → mount point `/boot/efi`. **Leave "Format" unticked** if it's shared.
  - Swap partition → Edit → Format → swap (or create one, at least the size of your RAM).
  - Free space → **+** → Partition, 2 GiB, ext4, mount point `/boot`.
  - Free space → **+** → **Btrfs Volume**, the remaining space. Then select that volume → **+** →
    **Btrfs Subvolume**, name `root`, mount point `/`. (Root on a subvolume, not the top level,
    keeps snapper rollbacks and boot-to-snapshot possible later.)
  - **Keeping an existing home?** Don't touch its partition and don't assign `/home` here.
  - Read the **Summary of Changes**: nothing should say destroy/format on partitions you're keeping.
- **Root Account:** disabled.
- **User Creation:** your user name, **administrator**. If you're keeping an existing home, set
  **Advanced… → User ID and Group ID = 1000** (or whatever owned the files before).

**Begin Installation** → **Reboot System**, remove the USB.

## 3. First boot (text console)

Fedora boots to a text login; that's expected. No internet? `nmcli device wifi connect "<SSID>" password "<password>"`.

**Keeping an existing home:** mount it at `/home` on every boot. For a btrfs subvolume (e.g. `@home`):

```bash
sudo blkid                                   # find the home partition's UUID
echo 'UUID=<uuid> /home btrfs subvol=@home,noatime,compress=zstd:1 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /home
sudo restorecon -Rv /home > /dev/null       # REQUIRED: SELinux labels for files from another distro
sudo reboot
```

Fresh home: get the repo first: `sudo dnf install -y git && git clone <this repo> ~/src/dotfiles`.

## 4. Scripts

```bash
cd ~/src/dotfiles
./install_desktop.sh                          # repos, niri + DMS, apps, services, snapper, hibernation
./install_cli.sh --sudo-access yes            # CLI tools via mise
./setup.sh -t n -g n -z y --sudo-access yes   # dotfiles (chezmoi), zsh, tmux plugins
./install_desktop.sh                          # second run: builds iio-niri now that cargo exists
sudo reboot                                   # → DMS login screen
```

Both install scripts are safe to re-run. `install_desktop.sh` ends with a list of manual steps.

## 5. After the install

- **Hibernation:** test with `systemctl hibernate`, then power on. Your session should come back.
- **Snapshots:** every dnf transaction takes a pre/post snapshot of `/`. Undo a bad update in
  **Btrfs Assistant** → Snapper, or `snapper -c root list` then `sudo snapper -c root undochange <pre>..<post>`.
- **Tailscale:** `sudo tailscale up` (or restore `/var/lib/tailscale` from a backup to keep the
  machine's identity).
- **VPN (UT Austin):** Cisco Secure Client; see the manual step printed by `install_desktop.sh`.
- **Media server** (`~/src/compose-files`): `docker compose pull`, then
  `systemctl --user enable --now media-server.service`. Docker CE doesn't enforce SELinux labels
  here, so the bind mounts need no `:z`.
- **Updates:** `sudo dnf upgrade` about weekly (kernel updates need a reboot). CLI tools update
  themselves weekly (mise timer).

### Optional: Limine as the boot menu

If Limine is already installed on the EFI partition (e.g. from a previous Arch/CachyOS install), it
can stay the boot menu and hand off to Fedora's GRUB:

```bash
sudo grub2-editenv - set menu_auto_hide=1          # GRUB's menu only shows if a boot fails
sudo find /boot/efi -name limine.conf               # then sudoedit it and add, as the first entry:
#   /Fedora
#     protocol: efi
#     path: boot():/EFI/fedora/shimx64.efi
efibootmgr                                          # note Limine's and Fedora's boot numbers
sudo efibootmgr -o <limine>,<fedora>                # Limine first, GRUB as fallback
```

Another OS's Limine tooling (e.g. CachyOS's `limine-entry-tool`) may rewrite `limine.conf` and drop
the Fedora entry; re-add it if so.

### Dual boot notes

If two OSes share the home partition or the swap partition: **never hibernate one and boot the
other** (it can corrupt files), and avoid switching back and forth a lot.
