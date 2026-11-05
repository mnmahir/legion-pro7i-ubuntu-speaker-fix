#!/usr/bin/env bash
# Legion Pro 7i Gen 10 / 16IAX10H (83F5), codec 17aa:3906 or 17aa:3907.
# Release 1.3.1 public edition, documented 2026-11-06. See the accompanying HTML for evidence.
# SPDX-License-Identifier: MIT (installer wrapper only)
# Vendor firmware is downloaded separately; no vendor binary is embedded.
# Upstream Linux downloaded separately: GPL-2.0-only and file-specific notices.
#
# MIT License — Copyright (c) 2026 Legion Speaker Fix contributors.
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE. This permission does not license separately downloaded vendor firmware.
set -Eeuo pipefail
umask 022
export LC_ALL=C
SCRIPT_VERSION=1.3.1
KERNEL=7.3.1
KREL=7.3.1-legion-aw88399
KSHA=fa595aad93734f829c963c2a90ef7c3673224fd7fdae7b49406e397cde2de231
FSHA=1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c
FW_URL=https://raw.githubusercontent.com/nadimkobeissi/16iax10h-linux-sound-saga/113031db46e1781ad55a2eafbcb284c2d7df9830/fix/firmware/aw88399_acf.bin
STATE=/var/lib/legion-speaker-fix
GRUB_FILE=/etc/default/grub.d/98-legion-speaker-fix.cfg
SELF=$(readlink -f -- "$0")
MODE=${1:---diagnose}
JOBS=${LEGION_BUILD_JOBS:-8}
say() { printf '\n%s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
has_native() {
  modinfo -k "${1:-$(uname -r)}" snd_hda_scodec_aw88399_i2c >/dev/null 2>&1 ||
    grep -qs '^CONFIG_SND_HDA_SCODEC_AW88399_I2C=y$' "/boot/config-${1:-$(uname -r)}"
}
secure_boot() { mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; }
identity() {
  local codec f
  [[ $(cat /sys/class/dmi/id/sys_vendor) == LENOVO ]] || die 'This script is for Lenovo hardware.'
  [[ $(cat /sys/class/dmi/id/product_version) == *16IAX10H* ]] || die 'Unsupported model. Expected Legion Pro 7 16IAX10H.'
  [[ $(uname -m) == x86_64 ]] || die 'Only x86_64 is supported.'
  codec=''
  for f in /proc/asound/card*/codec*; do
    [[ -r $f ]] || continue
    if grep -q 'Vendor Id: 0x10ec0287' "$f"; then
      codec=$(awk '/Subsystem Id:/ {print tolower($3); exit}' "$f")
    fi
  done
  [[ $codec == 0x17aa3906 || $codec == 0x17aa3907 ]] || die "Unsupported or unavailable ALC287 codec identity: ${codec:-none}. Boot with onboard audio enabled."
  compgen -G '/sys/bus/acpi/devices/AWDZ8399:*' >/dev/null || die 'AWDZ8399 ACPI device is missing.'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ $ID == ubuntu ]] || die 'This installer supports Ubuntu. Derivatives require separate review.'
  [[ ${VERSION_ID%%.*} -ge 22 ]] || die 'Ubuntu 22.04 or newer is required.'
  SSID=${codec#0x}
}
diagnose() {
  say "Legion speaker repair $SCRIPT_VERSION — read-only diagnosis"
  printf 'Model: '; cat /sys/class/dmi/id/product_version
  printf 'OS: '
  # shellcheck disable=SC1091
  . /etc/os-release
  printf '%s\n' "$PRETTY_NAME"
  printf 'Kernel: %s\nCodec SSID: %s\n' "$(uname -r)" "$SSID"
  if command -v mokutil >/dev/null; then mokutil --sb-state || true; fi
  if has_native; then say 'HDA woofer driver: available in the running kernel.'
  else say 'HDA woofer driver: MISSING. The ASoC chip driver alone is insufficient.'; fi
  for f in /lib/firmware/aw88399_acf.bin "/lib/firmware/awinic/aw88399_acf_$SSID.bin"; do
    if [[ -f $f ]]; then sha256sum "$f"; else printf 'Missing: %s (also check compressed firmware below)\n' "$f"; fi
    for ext in zst xz; do [[ ! -f $f.$ext ]] || ls -l "$f.$ext"; done
  done
  say 'AW88399 I2C devices and driver bindings:'
  for f in /sys/bus/i2c/devices/*AWDZ8399*; do
    [[ -e $f ]] || continue
    printf '%s -> %s\n' "$(basename "$f")" "$(readlink -f "$f/driver" 2>/dev/null || true)"
  done
  lsmod | grep -E 'aw88399|snd_hda_codec_alc269' || true
  journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'aw88399|ALC287: picked fixup|AWDZ8399' | tail -45 || true
  say 'This command changes nothing. Install: bash legion-speaker-fix.sh --install'
}
root_required() {
  [[ $EUID == 0 ]] || exec sudo -- bash "$SELF" "$MODE"
  [[ $JOBS =~ ^[1-9][0-9]*$ && $JOBS -le 32 ]] || die 'LEGION_BUILD_JOBS must be 1–32.'
  install -d -m 700 "$STATE" "$STATE/backups"
  exec 9>"$STATE/lock"
  flock -n 9 || die 'Another copy of this installer is running.'
  # Never log passwords or private keys. sudo and mokutil prompt locally.
  LOG="$STATE/$(date -u +%Y%m%dT%H%M%SZ)-${MODE#--}.log"
  exec > >(tee -a "$LOG") 2>&1
  trap 'failure "$?" "$LINENO"' ERR
  say "Legion speaker repair $SCRIPT_VERSION — ${MODE#--}"
}
failure() {
  printf '\nStopped at line %s (exit %s). The old kernel remains installed. Log: %s\n' "$2" "$1" "$LOG" >&2
  exit "$1"
}
backup() {
  local path=$1 name
  name=$(printf '%s' "$path" | tr / _)
  if [[ ! -e $STATE/backups/$name && ! -e $STATE/backups/$name.absent ]]; then
    if [[ -e $path ]]; then cp -a -- "$path" "$STATE/backups/$name";
    else : > "$STATE/backups/$name.absent"; fi
  fi
}
firmware() {
  local tmp path missing=0
  local -a paths=(/lib/firmware/aw88399_acf.bin /lib/firmware/awinic/aw88399_acf_17aa3906.bin /lib/firmware/awinic/aw88399_acf_17aa3907.bin)
  for path in "${paths[@]}"; do
    if [[ ! -e $path && ! -e $path.zst && ! -e $path.xz ]]; then missing=1; fi
  done
  if (( ! missing )); then
    say 'Existing AW88399 firmware layouts found; no firmware download needed.'
    return 0
  fi
  tmp=$(mktemp "$STATE/firmware.XXXXXX")
  if ! command -v curl >/dev/null; then
    apt-get update
    apt-get install -y curl ca-certificates
  fi
  say 'Downloading AW88399 firmware from the pinned upstream source.'
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 "$FW_URL" -o "$tmp"
  [[ $(sha256sum "$tmp" | awk '{print $1}') == "$FSHA" ]] || die 'Firmware integrity check failed; no firmware file was installed.'
  for path in "${paths[@]}"; do
    if [[ -e $path || -e $path.zst || -e $path.xz ]]; then
      say "Keeping existing firmware: $path (or compressed variant)"
      continue
    fi
    backup "$path"
    install -D -m 644 "$tmp" "$path"
    printf '%s\n' "$path" >> "$STATE/firmware-created"
  done
  rm -f -- "$tmp"
}
conflicts() {
  local hits
  hits=$(grep -REin '^[[:space:]]*(options.*(dsp_driver|model)=|blacklist.*(snd_hda|aw88399)|.*snd_intel_dspcfg[.]dsp_driver=)' /etc/modprobe.d /etc/default/grub /etc/default/grub.d 2>/dev/null || true)
  [[ -z $hits ]] || die "Existing audio overrides need review before native installation. Script will not overwrite them:
$hits"
  if command -v dkms >/dev/null && dkms status | grep -qi 'aw88399'; then
    die 'An older AW88399 DKMS driver is registered. Remove it using its own package/uninstaller before using native support.'
  fi
}
grub_entry() {
  python3 - "$1" <<'PY'
import re,sys
version=sys.argv[1]
text=open('/boot/grub/grub.cfg').read()
submenu=None
for line in text.splitlines():
    if line.lstrip().startswith('submenu '):
        m=re.search(r"(?:--id|\$menuentry_id_option)\s+'([^']+)'",line)
        if m and 'advanced' in m[1]: submenu=m[1]
    if line.lstrip().startswith('menuentry ') and f'with Linux {version}' in line and 'recovery mode' not in line:
        m=re.search(r"(?:--id|\$menuentry_id_option)\s+'([^']+)'",line)
        if m and submenu:
            print(submenu+'>'+m[1]);sys.exit(0)
sys.exit('Cannot locate the exact kernel entry in GRUB; no boot selection changed.')
PY
}
set_grub_default() {
  local entry=$1
  [[ $entry =~ ^[a-zA-Z0-9_\>.-]+$ ]] || die 'Unexpected GRUB entry identifier.'
  backup "$GRUB_FILE"
  install -d /etc/default/grub.d
  printf '# Managed by legion-speaker-fix.sh; old kernels remain installed.\nGRUB_DEFAULT="%s"\nGRUB_TIMEOUT_STYLE=menu\nGRUB_TIMEOUT=10\n' "$entry" > "$GRUB_FILE"
  update-grub
}
make_key() {
  install -d -m 700 "$STATE/keys"
  if [[ ! -f $STATE/keys/boot.key ]]; then
    openssl req -new -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
      -subj '/CN=Legion local kernel boot key/' \
      -addext 'basicConstraints=critical,CA:FALSE' -addext 'keyUsage=digitalSignature' \
      -addext 'extendedKeyUsage=codeSigning' \
      -keyout "$STATE/keys/boot.key" -out "$STATE/keys/boot.pem"
    chmod 600 "$STATE/keys/boot.key"
    openssl x509 -in "$STATE/keys/boot.pem" -outform DER -out "$STATE/keys/boot.der"
  fi
}
certificate_in_mok_list() {
  local cert=$1 list_mode=$2 fingerprint enrolled
  [[ $list_mode == --list-enrolled || $list_mode == --list-new ]] || return 1
  [[ -r $cert && -s $cert ]] || return 1
  fingerprint=$(openssl x509 -inform DER -in "$cert" -noout -fingerprint -sha1 2>/dev/null) || return 1
  fingerprint=${fingerprint#*=}
  [[ $fingerprint =~ ^([[:xdigit:]]{2}:){19}[[:xdigit:]]{2}$ ]] || return 1
  enrolled=$(mokutil "$list_mode" 2>/dev/null) || return 1
  # Compare the exact certificate identity in the authoritative MOK list.
  # Compare fingerprints directly; do not assume --test-key exits zero when enrolled.
  printf '%s\n' "$enrolled" | awk -v expected="$fingerprint" '
    /^[[:space:]]*SHA1 Fingerprint:/ {
      line=$0; sub(/^[[:space:]]*SHA1 Fingerprint:[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if (tolower(line)==tolower(expected)) found=1
    }
    END {exit !found}'
}
certificate_enrolled() { certificate_in_mok_list "$1" --list-enrolled; }
enroll_keys() {
  local cert
  local -a pending_certs=()
  secure_boot || return 0
  for cert in "$STATE/keys/boot.der" /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub; do
    [[ -f $cert ]] || continue
    if ! certificate_enrolled "$cert"; then
      pending_certs+=("$cert")
    fi
  done
  if (( ${#pending_certs[@]} )); then
      say "Secure Boot needs these public certificates enrolled:
${pending_certs[*]}
Choose a temporary password below. At reboot: Enroll MOK → Continue → Yes → enter that password.
Keep the password private; it is used on your laptop only."
      # Submit one request: repeated --import calls can replace the pending set.
      mokutil --import "${pending_certs[@]}"
      for cert in "${pending_certs[@]}"; do
        certificate_in_mok_list "$cert" --list-new || die "Cannot verify the pending enrollment request for $cert. The trial kernel will not be selected."
      done
  fi
}
boot_key_trusted() {
  secure_boot || return 0
  certificate_enrolled "$STATE/keys/boot.der"
}
schedule_trial_boot() {
  if ! boot_key_trusted; then
    say 'SECURE BOOT ENROLLMENT REQUIRED — the original kernel stays selected.
Reboot, press a key when MOK Manager offers enrollment, then choose:
Enroll MOK → Continue → Yes → enter your temporary enrollment password → Reboot.
After returning to Ubuntu, run: bash legion-speaker-fix.sh --boot-repair
That command checks enrollment before selecting the trial kernel. No rebuild is needed.'
    return 0
  fi
  update-grub
  grub-reboot "$(grub_entry "$KREL")"
  say "READY FOR ONE TRIAL BOOT: $KREL
Before reboot, lower built-in speaker volume to 15–20% in Ubuntu Settings.
Reboot when ready. The original kernel stays the normal default until --commit.
To cancel the trial: sudo grub-editenv /boot/grub/grubenv unset next_entry
After reboot: bash legion-speaker-fix.sh --verify"
}
repair_boot() {
  [[ -s $STATE/original-grub-entry ]] || die 'No recorded custom-kernel installation was found.'
  [[ -s /boot/vmlinuz-$KREL && -s /boot/initrd.img-$KREL ]] || die 'The custom kernel or its boot image is missing. Finish --install first.'
  set_grub_default "$(cat "$STATE/original-grub-entry")"
  grub-editenv /boot/grub/grubenv unset next_entry
  if secure_boot; then
    [[ -s $STATE/keys/boot.key && -s $STATE/keys/boot.pem && -s $STATE/keys/boot.der ]] || die 'The local boot-signing key is missing. Run --install to complete signing.'
    # The boot certificate must be the same public certificate in PEM and DER.
    [[ $(openssl x509 -in "$STATE/keys/boot.pem" -outform DER | sha256sum | awk '{print $1}') == "$(sha256sum "$STATE/keys/boot.der" | awk '{print $1}')" ]] || die 'Stored public boot certificates do not match; no new enrollment requested.'
    if ! sbverify --cert "$STATE/keys/boot.pem" "/boot/vmlinuz-$KREL"; then
      say 'Restoring the kernel image signature using its existing local boot key.'
      sbsign --key "$STATE/keys/boot.key" --cert "$STATE/keys/boot.pem" \
        --output "$STATE/vmlinuz.signed" "/boot/vmlinuz-$KREL"
      sbverify --cert "$STATE/keys/boot.pem" "$STATE/vmlinuz.signed"
      install -m 600 "$STATE/vmlinuz.signed" "/boot/vmlinuz-$KREL"
    fi
    say 'Boot certificate to enroll (public information):'
    openssl x509 -in "$STATE/keys/boot.pem" -noout -subject -fingerprint -sha256
    if ! boot_key_trusted; then
      say 'The kernel boot key is not enrolled. Choose a temporary password below.
Use this password only on your laptop in MOK Manager; do not share it in chat.'
      mokutil --import "$STATE/keys/boot.der"
      certificate_in_mok_list "$STATE/keys/boot.der" --list-new || die 'The public boot certificate was not found in the pending MOK request. No trial boot selected.'
      say 'Confirmed: the local boot certificate is now queued for MOK enrollment.'
    fi
  fi
  schedule_trial_boot
}
prepare_nvidia_policy() {
  local policy=/etc/dkms/nvidia.conf
  if [[ -e $policy ]] && ! grep -q '^# Managed by legion-speaker-fix.sh: retain matching Ubuntu NVIDIA modules$' "$policy"; then
    die 'An existing /etc/dkms/nvidia.conf needs review before this installer can add its NVIDIA coexistence policy.'
  fi
  backup "$policy"
  install -d /etc/dkms
  cat > "$policy" <<'NVIDIA_POLICY'
# Managed by legion-speaker-fix.sh: retain matching Ubuntu NVIDIA modules
# DKMS sources this AFTER the module's packaged dkms.conf.
# A stock Ubuntu module already at this exact version needs no replacement.
# Custom kernels, absent modules and different versions still build normally.
if [[ -n ${kernelver:-} && -n ${PACKAGE_VERSION:-} ]]; then
  _legion_nv_file=$(modinfo -k "$kernelver" -F filename nvidia 2>/dev/null || true)
  _legion_nv_version=$(modinfo -k "$kernelver" -F version nvidia 2>/dev/null || true)
  if [[ $_legion_nv_file == */kernel/nvidia-*/* && $_legion_nv_version == "$PACKAGE_VERSION" ]]; then
    BUILD_EXCLUSIVE_KERNEL='^$'
  fi
  unset _legion_nv_file _legion_nv_version
fi
NVIDIA_POLICY
  chmod 644 "$policy"
}
recover_nvidia_package() {
  local package
  while IFS= read -r package; do
    [[ -n $package ]] || continue
    say "Completing interrupted NVIDIA package configuration: $package"
    dpkg --configure "$package"
  done < <(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' 'nvidia-dkms-*' 2>/dev/null |
    awk '$1 ~ /^(half-configured|unpacked|half-installed)$/ && $2 ~ /^nvidia-dkms-[0-9]+(-open)?$/ {print $2}' || true)
}
cached_kernel_packages() {
  local kind file
  local -a files
  for kind in headers image; do
    files=("$STATE"/packages/linux-"$kind"-"$KREL"_*.deb)
    [[ ${#files[@]} -eq 1 && -s ${files[0]} ]] || return 1
    file=${files[0]}
    [[ $(dpkg-deb -f "$file" Package) == "linux-$kind-$KREL" ]] || return 1
    [[ $(dpkg-deb -f "$file" Version) == 7.3.1-1 ]] || return 1
    [[ $(dpkg-deb -f "$file" Architecture) == amd64 ]] || return 1
  done
}
build_native_kernel() {
  local caller build src archive free base_kernel pkg nvpkg nvdkms module
  caller=${SUDO_USER:-}
  [[ -n $caller && $caller != root ]] || die 'Run --install from your normal desktop account with bash, rather than from a root shell.'
  command -v update-grub >/dev/null || die 'The custom-kernel route currently requires Ubuntu with GRUB.'
  [[ -r /boot/grub/grub.cfg ]] || die 'GRUB configuration unavailable.'
  command -v update-initramfs >/dev/null || die 'initramfs-tools is required.'
  base_kernel=$(uname -r)
  if [[ ! -f $STATE/original-kernel ]]; then
    printf '%s\n' "$base_kernel" > "$STATE/original-kernel"
    grub_entry "$base_kernel" > "$STATE/original-grub-entry"
  fi
  # Protect the original boot before any kernel-package post-install hook runs.
  set_grub_default "$(cat "$STATE/original-grub-entry")"
  # Recover a previous collision BEFORE any apt transaction retries its postinst.
  nvpkg=$(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' 'nvidia-driver-*' 2>/dev/null | awk '$1=="installed" && $2 ~ /^nvidia-driver-[0-9]+(-open)?$/ {print $2;exit}' || true)
  if [[ -n $nvpkg ]]; then
    prepare_nvidia_policy
    recover_nvidia_package
  fi
  build=$(getent passwd "$caller" | cut -d: -f6)/.cache/legion-speaker-fix
  [[ $build != *' '* ]] || die 'Kernel builds need a path without spaces.'
  install -d -m 700 -o "$caller" -g "$(id -gn "$caller")" "$build"
  free=$(df --output=avail -BM /boot | tail -1 | tr -dc '0-9')
  [[ $free -ge 450 ]] || die 'Allow at least 450 MiB free in /boot.'
  if cached_kernel_packages; then
    say 'Using the completed kernel packages from the previous run. The full kernel build will be skipped.'
  else
  free=$(df --output=avail -BG "$build" | tail -1 | tr -dc '0-9')
  [[ $free -ge 35 ]] || die 'Allow at least 35 GiB free in your account cache for a full native kernel build.'
  apt-get update
  apt-get install -y build-essential gcc g++ bc bison flex gawk cpio kmod rsync xz-utils zstd \
    libelf-dev libdw-dev libssl-dev libncurses-dev dpkg-dev debhelper python3 curl \
    initramfs-tools mokutil openssl sbsigntool dkms
  archive="$build/linux-$KERNEL.tar.xz"
  if [[ ! -f $archive ]] || [[ $(sha256sum "$archive" | awk '{print $1}') != "$KSHA" ]]; then
    runuser -u "$caller" -- curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
      "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KERNEL.tar.xz" -o "$archive"
  fi
  [[ $(sha256sum "$archive" | awk '{print $1}') == "$KSHA" ]] || die 'Kernel source checksum mismatch.'
  src="$build/linux-$KERNEL"
  if [[ ! -f $src/Makefile ]]; then runuser -u "$caller" -- tar -xJf "$archive" -C "$build"; fi
  if [[ ! -f $src/.legion-configured ]]; then
    install -o "$caller" -g "$(id -gn "$caller")" -m 644 "/boot/config-$base_kernel" "$src/.config"
    runuser -u "$caller" -- bash -s -- "$src" <<'BUILD_CONFIG'
set -euo pipefail
cd "$1"
scripts/config --set-str LOCALVERSION '-legion-aw88399' --disable LOCALVERSION_AUTO \
  --set-str SYSTEM_TRUSTED_KEYS '' --set-str SYSTEM_REVOCATION_KEYS '' \
  --set-str MODULE_SIG_KEY 'certs/signing_key.pem' --enable MODULE_SIG --enable MODULE_SIG_ALL \
  --disable DEBUG_INFO_DWARF5 --disable DEBUG_INFO_DWARF4 \
  --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE --disable DEBUG_INFO_BTF \
  --disable DEBUG_INFO_BTF_MODULES --disable RUST \
  --module SND_HDA_INTEL --module SND_HDA_CODEC_REALTEK --module SND_SOC \
  --module SND_HDA_SCODEC_AW88399_I2C --module SERIAL_MULTI_INSTANTIATE
make olddefconfig
grep -q '^CONFIG_SND_HDA_SCODEC_AW88399_I2C=m$' .config
touch .legion-configured
BUILD_CONFIG
  fi
  say "Building Linux $KERNEL with the upstream AW88399 fix; $JOBS build jobs.
This may take an hour or more. A rerun resumes the same build. Keep AC power connected."
  runuser -u "$caller" -- bash -s -- "$src" "$JOBS" <<'BUILD_KERNEL'
set -euo pipefail
cd "$1"
make -j"$2" bindeb-pkg KDEB_PKGVERSION=7.3.1-1
BUILD_KERNEL
  # Copy only completed local packages into a root-owned staging directory.
  install -d -m 700 "$STATE/packages"
  for pkg in "$build"/linux-headers-"$KREL"_*.deb "$build"/linux-image-"$KREL"_*.deb; do
    [[ -f $pkg ]] || die "Expected local kernel package missing: $pkg"
    install -m 600 "$pkg" "$STATE/packages/$(basename "$pkg")"
  done
  fi
  # Ensure the matching NVIDIA branch can be built for a non-Ubuntu kernel.
  nvpkg=$(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' 'nvidia-driver-*' 2>/dev/null | awk '$1=="installed" && $2 ~ /^nvidia-driver-[0-9]+(-open)?$/ {print $2;exit}' || true)
  if [[ -n $nvpkg ]]; then
    nvdkms=${nvpkg/nvidia-driver-/nvidia-dkms-}
    apt-get install -y "$nvdkms"
  fi
  # Header postinst and image postinst run DKMS. A failure stops before trial boot.
  dpkg -i "$STATE"/packages/linux-headers-"$KREL"_*.deb
  dpkg -i "$STATE"/packages/linux-image-"$KREL"_*.deb
  depmod -a "$KREL"
  has_native "$KREL" || die 'New kernel does not expose the required AW88399 HDA driver.'
  # Check essential drivers currently in use also exist for the candidate.
  for module in i915 xe iwlwifi btusb nvme ext4 nvidia evdi; do
    if [[ -d /sys/module/$module ]]; then
      modinfo -k "$KREL" "$module" >/dev/null 2>&1 || die "Candidate is missing an active driver: $module. Old default retained."
    fi
  done
  if secure_boot; then
    make_key
    sbsign --key "$STATE/keys/boot.key" --cert "$STATE/keys/boot.pem" \
      --output "$STATE/vmlinuz.signed" "/boot/vmlinuz-$KREL"
    sbverify --cert "$STATE/keys/boot.pem" "$STATE/vmlinuz.signed"
    install -m 600 "$STATE/vmlinuz.signed" "/boot/vmlinuz-$KREL"
    # The build-generated module certificate validates all native modules;
    # DKMS uses its existing Ubuntu/DKMS MOK, enrolled below if needed.
  fi
  update-initramfs -u -k "$KREL"
  [[ -s /boot/initrd.img-$KREL ]] || die 'Candidate initramfs missing.'
  enroll_keys
  schedule_trial_boot
}
install_fix() {
  conflicts
  firmware
  if has_native; then
    update-initramfs -u -k "$(uname -r)"
    say 'Firmware is ready. Reboot to probe the amplifiers, then run --verify. No kernel replacement is needed.'
  else
    # Never downgrade a future kernel that simply disabled the driver.
    if dpkg --compare-versions "$(uname -r | cut -d- -f1)" ge 7.3; then
      die 'This newer kernel omitted the AW88399 HDA config. Use an Ubuntu kernel with CONFIG_SND_HDA_SCODEC_AW88399_I2C=m; this script will not downgrade it.'
    fi
    build_native_kernel
  fi
}
verify() {
  local f bound=0 errors=0
  diagnose
  has_native || errors=$((errors+1))
  for f in /sys/bus/i2c/devices/*AWDZ8399*; do
    [[ -L $f/driver ]] || continue
    if [[ $(basename "$(readlink -f "$f/driver")") == *aw88399*hda* ]]; then bound=$((bound+1)); fi
  done
  printf '\nHDA amplifier bindings: %s / 2\n' "$bound"
  [[ $bound -ge 2 ]] || errors=$((errors+1))
  if command -v wpctl >/dev/null; then wpctl status || true; fi
  if ((errors)); then say 'Verification incomplete: inspect the boot log above. Driver presence alone does not prove working sound.'; return 2; fi
  say 'Driver and two-amplifier binding checks passed. Audible output is still unverified.
Select Built-in Audio / Speakers, unplug headphones, start at 15–20% volume and play familiar music.
Check left/right, volume scaling, headphone switching, microphone, and audio after suspend/resume.
After those pass, keep the new kernel with: bash legion-speaker-fix.sh --commit'
}
commit() {
  [[ $(uname -r) == "$KREL" ]] || die "Boot $KREL and perform listening tests before --commit."
  verify
  boot_key_trusted || die 'The custom kernel boot key is not present in the enrolled certificate list.'
  set_grub_default "$(grub_entry "$KREL")"
  say 'The tested kernel is now the default. The old Ubuntu kernel remains in Advanced options.
This custom upstream kernel receives NO automatic Ubuntu kernel security updates.
Move back to a supported Ubuntu kernel with native AW88399 HDA support when available.
Use --rollback to select the original kernel. Keep normal Ubuntu updates enabled.'
}
rollback() {
  [[ -s $STATE/original-grub-entry ]] || die 'No custom-kernel installation is recorded. No boot selection changed.'
  set_grub_default "$(cat "$STATE/original-grub-entry")"
  grub-editenv /boot/grub/grubenv unset next_entry
  say "Original kernel selected for the next boot: $(cat "$STATE/original-kernel")
Reboot when ready. Firmware and kernel packages remain available for diagnosis.
No other audio configuration was changed by this installer."
}
help_text() {
  cat <<'HELP'
Legion Pro 7i Gen 10 speaker repair
  bash legion-speaker-fix.sh --diagnose   Read-only; also the default
  bash legion-speaker-fix.sh --install    Install firmware; if necessary build native Linux 7.3.1
  bash legion-speaker-fix.sh --boot-repair  Enroll/check the existing boot key; schedule a trusted trial
  bash legion-speaker-fix.sh --verify     Check drivers/bindings; then perform listening tests
  bash legion-speaker-fix.sh --commit     Keep the tested custom kernel as default
  bash legion-speaker-fix.sh --rollback   Select original Ubuntu kernel; cancel trial boot
  bash legion-speaker-fix.sh --help
Internet is needed for Ubuntu build tools and ~155 MiB kernel source on older kernels.
Allow >=35 GiB free in your account's cache and >=450 MiB in /boot.
Firmware is downloaded from a pinned upstream URL and hash checked.
Existing firmware is retained. Kernel source and firmware checksums are pinned.
The custom kernel path needs Ubuntu, GRUB, an interactive desktop account and AC power.
Secure Boot stays enabled: a local boot key may require enrollment at reboot.
No automatic reboot. No volume boosting, codec register writes or forced SOF mode.
Future Ubuntu: if its kernel already includes the HDA side codec, only missing firmware is installed.
Unknown hardware/configurations stop with a diagnostic instead of guessing.
HELP
}
case "$MODE" in
  --help|-h) help_text; exit 0;;
  --diagnose|--verify|--install|--boot-repair|--commit|--rollback) ;;
  *) help_text; die "Unknown mode: $MODE";;
esac
[[ $# -le 1 ]] || die 'Pass one mode at a time.'
identity
case "$MODE" in
  --diagnose) diagnose;;
  --verify) verify;;
  --install) root_required; install_fix;;
  --boot-repair) root_required; repair_boot;;
  --commit) root_required; commit;;
  --rollback) root_required; rollback;;
esac
