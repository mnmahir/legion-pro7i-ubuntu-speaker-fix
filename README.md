# Legion Pro 7i Gen 10 speaker repair for Ubuntu

A hardware-specific installer and interactive guide for the **Lenovo Legion Pro 7 16IAX10H**. It addresses the tweeter-only, quiet or thin sound associated with an inactive **Awinic AW88399 woofer path**.

The upstream audio-driver work is credited to [the 16IAX10H Linux sound project](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga). This project supplies an Ubuntu installation wrapper, verification and rollback commands, and a self-contained illustrated explanation.

<a href='https://ko-fi.com/H2H818H9M3' target='_blank' rel='noopener noreferrer'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi2.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

## Read the guide

Download [LegionPro7i_Speaker_Guide.html](LegionPro7i_Speaker_Guide.html) and open it in a modern browser. The guide includes seven chapters, 2D/3D simulations, boot replay, script download, a local diagnosis interpreter and a printable layout. The simulations do not inspect hardware or measure speaker output.

The guide opens offline. The public installer downloads firmware and, on the custom-kernel path, source and build dependencies. **No vendor firmware binary, machine log, signing key or personal hardware snapshot is included in this repository.**

## Compatibility and test scope

| Item | Scope |
| --- | --- |
| Model | Lenovo Legion Pro 7 16IAX10H, Intel, x86_64; reference DMI product 83F5 |
| Codec | Realtek ALC287, codec SSID `17aa:3906` or `17aa:3907` |
| Amplifiers | Awinic AW88399, ACPI HID `AWDZ8399` |
| Ubuntu guard | Ubuntu 22.04 or newer; custom-kernel route requires GRUB |
| End-to-end tested | Ubuntu 24.04.5, codec `17aa:3906`, Linux `7.3.1-legion-aw88399`, Secure Boot enabled |
| Reference result | Two HDA amplifier bindings; restored bass and normal loudness reported |

Only one physical configuration was validated end to end, on **6 November 2026**. Codec `3907`, other Ubuntu releases, derivatives and other Legion models are not independently validated with this wrapper. There are no acoustic measurements or confirmed headphone, microphone or suspend/resume results. The [tested configuration](manifest.json) is reference evidence, not a statement about the computer reading this page.

## Diagnose first

Download [legion-speaker-fix.sh](legion-speaker-fix.sh), inspect its source, and run it from a terminal:

```bash
bash legion-speaker-fix.sh --diagnose
```

The default mode is also read-only diagnosis. The script rejects unsupported model, codec, ACPI and operating-system identities.

## Install

Lower built-in speaker volume to **15–20%** before installation or testing:

```bash
bash legion-speaker-fix.sh --install
```

- **Native HDA driver available:** install missing firmware and refresh the current boot image.
- **Older kernel missing the driver:** build pinned upstream Linux 7.3.1 locally, package it, prepare matching NVIDIA DKMS support when applicable, and retain the existing kernel.

The build route needs AC power, internet, **35 GiB** free in the account cache and **450 MiB** free in `/boot`. It can take an hour or more. Completed kernel packages are reused after an interrupted run.

The custom kernel is pinned for reproducibility and **does not receive automatic Ubuntu kernel security updates**. Keep Ubuntu updates enabled and migrate to a supported Ubuntu kernel with native AW88399 support when available. This installer is not a kernel-update service.

## Secure Boot and the trial boot

If enrollment is required:

1. Run `bash legion-speaker-fix.sh --boot-repair` and choose a temporary enrollment password locally.
2. Wait for confirmation that the public certificate is queued. Reboot and complete **Enroll MOK → Continue → Yes** in MOK Manager.
3. After returning to Ubuntu, run `--boot-repair` again. It checks the exact enrolled-certificate fingerprint before reporting **READY FOR ONE TRIAL BOOT**.
4. Reboot into the trial kernel and check `uname -r`. On the custom route, expect `7.3.1-legion-aw88399`.

The native distribution-kernel path does not require this custom-kernel sequence. The script never reboots automatically and does not disable Secure Boot.

## Verify and keep the result

```bash
bash legion-speaker-fix.sh --verify
```

Check for the HDA driver and `HDA amplifier bindings: 2 / 2`, then test familiar music at low volume. Also check left/right, volume and mute, headphones, microphone, suspend/resume and the displays/network devices used with the laptop.

After a successful custom-kernel trial:

```bash
bash legion-speaker-fix.sh --commit
```

To select the previous kernel again:

```bash
bash legion-speaker-fix.sh --rollback
```

If the desktop cannot boot, select the previous kernel under GRUB’s **Advanced options for Ubuntu** first. Rollback changes boot selection; it retains firmware, packages, keys, the NVIDIA coexistence rule and logs. It is not a full uninstall.

## Firmware and integrity

The public edition downloads `aw88399_acf.bin` from [this commit-pinned upstream file](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga/blob/113031db46e1781ad55a2eafbcb284c2d7df9830/fix/firmware/aw88399_acf.bin). It verifies SHA-256 before installing any firmware file:

```text
1e927c9bca76d868181c0f81df2bccef3cf19c7d0910219f229360c87babd42c
```

Existing firmware, including compressed variants, is retained. Firmware is not included in the HTML, script or repository, and is not covered by this project’s MIT license. Kernel source has a separate pinned hash and retains its upstream licenses. [manifest.json](manifest.json) records URLs, hashes and test scope.

## Troubleshooting and reports

Logs are written to `/var/lib/legion-speaker-fix`; backups and locally generated signing keys stay on the target computer. Do not include private keys in reports.

For a useful issue report, include the model and codec IDs, Ubuntu and kernel versions, script release, exact failing step, and relevant diagnosis/log lines. Review output for personal details before posting it. A matching model name or a successful driver binding alone does not prove that an audible repair succeeded.

## Credits and license

- [16IAX10H Linux sound saga](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga): driver work and firmware instructions; credits include Yakov Till / Lyapsus, Nadim Kobeissi and Marco Giunta.
- [Linux kernel patch discussion](https://lkml.iu.edu/hypermail/linux/kernel/2607.2/03686.html): AW88399 integration and model quirks.
- [Canonical Secure Boot documentation](https://documentation.ubuntu.com/security/security-features/platform-protections/secure-boot/): signing and enrollment workflow.

The original installer wrapper, guide text and schematic graphics use the [MIT license](LICENSE). The third-party Ko-fi button artwork is excluded from that license grant. Linux, third-party packages and separately downloaded vendor firmware keep their own licenses. This is a community project, not an official Lenovo or Ubuntu support package.
