# 🖥️ Vast.ai Host Setup

> **One command to list your GPU machine on Vast.ai and start earning.**

![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Ubuntu%2022.04%2B-blue?logo=linux)
![GPU](https://img.shields.io/badge/GPU-NVIDIA%20Required-green?logo=nvidia)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)

---

## 🚀 Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vastai-host-setup/main/setup.sh -o setup.sh
sudo bash setup.sh
```

> Answer the prompts → forward ports on router → done. Machine live in **~5 minutes**.

---

## 🖥️ Can I List My Device?

| Device | Supported | Notes |
|--------|:---------:|-------|
| 🐧 Linux + NVIDIA GPU | ✅ **Yes** | Full support — best earnings |
| 🐧 Linux + AMD GPU | ⚠️ Partial | Limited workload support |
| 🪟 Windows | ❌ No | Kaalia daemon is Linux-only |
| 🍎 Mac (Intel / Apple Silicon) | ❌ No | No CUDA support |
| 🍓 Raspberry Pi / ARM | ❌ No | Requires x86_64 |

> 💡 You can **manage** your machines from any device (Mac, Windows, Linux) via SSH.
> The **machine being listed** must be Linux with NVIDIA GPU.

---

## 📋 Before You Start

| Requirement | Details |
|-------------|---------|
| 🐧 OS | Ubuntu 22.04 / 24.04 or Debian 12 |
| 🎮 GPU | NVIDIA RTX / Tesla / A-series with drivers |
| 🧠 RAM | **Must be ≥ GPU VRAM** *(e.g. RTX 5080 16GB → need 17GB+ RAM)* |
| 💾 Storage | 200 GB+ SSD recommended |
| 🌐 Internet | 100 Mbps+ (500 Mbps+ for verified badge) |
| 🔑 Account | [Vast.ai](https://vast.ai) account + API key |
| 🔀 Router | Access to add port forwarding rules |

Get your API key: **[console.vast.ai → Account → API Keys](https://console.vast.ai/)**

---

## 📦 Setup in 3 Steps

### Step 1 — Download & Run

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vastai-host-setup/main/setup.sh -o setup.sh
sudo bash setup.sh
```

### Step 2 — Answer the Prompts

The script will ask for:

| Prompt | Example | Where to Find |
|--------|---------|---------------|
| `Vast.ai API key` | `3ff927d1...` | [console.vast.ai → Account](https://console.vast.ai/) |
| `Hostname` | `gpu-rig-1` | Your choice |
| `Machine number` | `1` | Sequential per machine (1, 2, 3...) |
| `Public IP` | `203.0.113.1` | Auto-detected or check [whatismyip.com](https://whatismyip.com) |
| `LAN IP` | `192.168.0.100` | Fixed internal IP for this machine |
| `GPU price ($/hr)` | `0.20` | Check [vast.ai marketplace](https://vast.ai) for rates |

### Step 3 — Configure Router Port Forwarding

The script tells you **exactly which ports to forward**. Example for 4 machines:

```
📡 Machine 1 → forward ports 20000–20499 → 192.168.0.X
📡 Machine 2 → forward ports 20500–20999 → 192.168.0.Y
📡 Machine 3 → forward ports 21000–21499 → 192.168.0.Z
📡 Machine 4 → forward ports 21500–21999 → 192.168.0.W
```

---

## 🔧 What Gets Installed

| Component | Purpose |
|-----------|---------|
| **Kaalia daemon** | Vast.ai host agent (manages containers) |
| **NVIDIA container toolkit** | GPU access inside Docker |
| **Static IP (netplan)** | Stable LAN IP that survives reboots |
| **dmidecode sudoers** | Lets Kaalia read CPU info |
| **Auto-cleanup timer** | Hourly cleanup after rentals (frees disk) |
| **vastai CLI** | Command line tool to manage listings |

---

## 💻 Multiple Machines Setup

Run `setup.sh` on **each machine separately**. Enter a different machine number each time.
All machines can share **one public IP** — unique port ranges separate them.

```bash
# Machine 1
sudo bash setup.sh  # enter machine number: 1

# Machine 2 (different LAN IP, same router)
sudo bash setup.sh  # enter machine number: 2
```

---

## 🛠️ Commands Reference

```bash
# Full health check
bash scripts/status.sh

# Clean up after a rental (docker prune + fstrim)
sudo bash scripts/cleanup_now.sh

# Refresh 90-day marketplace listing
bash scripts/relist.sh

# Push this repo to GitHub
bash push.sh "your message"
```

---

## 📊 After Setup — Dashboard

Check your machines at **[console.vast.ai/host/machines](https://console.vast.ai/host/machines)**

What you'll see:
- 🟢 **Verified** — passed self-test (all GPU tests + RAM ≥ VRAM)
- 🟡 **Unverified** — listed but self-test not passed yet
- 💰 **Earnings** — shown per hour and per day
- 🌡️ **GPU Temp** — live temperature monitoring
- 📶 **Internet speed** — upload/download in Mbps

---

## 🔴 Common Issues & Fixes

| ❌ Problem | ✅ Fix |
|-----------|--------|
| "Unknown CPU" on dashboard | `sudo systemctl restart vastai.service` |
| Internet speed shows 0 | Wait 10 min after setup — auto-reports |
| Self-test: **RAM < VRAM** | Add physical RAM — cannot be bypassed |
| Self-test: **No offers found** | `bash scripts/relist.sh` |
| Non-GPU containers fail | Remove `"default-runtime":"nvidia"` from `/etc/docker/daemon.json` |
| `vastai_bouncer` service fails | `sudo systemctl disable --now vastai_bouncer.service` |
| Speed stuck low | Restart kaalia: `sudo systemctl restart vastai.service` |

---

## 🌐 Managing from Any Device

You manage your Linux GPU machines via SSH from anywhere:

**Mac or Linux:**
```bash
ssh youruser@192.168.0.X    # local network
ssh youruser@YOUR_PUBLIC_IP  # over internet (if SSH port forwarded)
```

**Windows:**
- [Windows Terminal](https://aka.ms/terminal) → `ssh youruser@ip`
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh)
- [PuTTY](https://putty.org)

---

## ⚠️ Verification Requirements

| Requirement | Status |
|-------------|--------|
| GPU tests (ResNet, ECC, NCCL, stress) | Tested by self-test |
| RAM ≥ GPU VRAM | Hard requirement — can't bypass |
| Internet ≥ 500 Mbps | For verified badge (machine still rents without it) |

Run self-test manually:
```bash
vastai self-test machine --ignore-requirements YOUR_MACHINE_ID
```

---

## 🔄 Auto Cleanup (Runs After Every Rental)

A systemd timer fires every hour. If no rental is running it:
1. 🗑️ Removes stopped containers
2. 🧹 Clears Docker build cache
3. 💾 Runs `fstrim` to return freed blocks to OS

Keeps disk at **4–9% used** when idle instead of filling up over time.

---

## 📁 Folder Structure

```
vastai-host-setup/
├── setup.sh              ← Main setup (run this)
├── push.sh               ← One-click git push
├── README.md             ← This file
├── .gitignore
└── scripts/
    ├── status.sh         ← Health check
    ├── cleanup_now.sh    ← Manual cleanup
    └── relist.sh         ← Refresh marketplace listing
```

---

## 📄 License

MIT — free to use and modify.

---

<div align="center">
Made for GPU hosts who want a clean, automated Vast.ai setup.
</div>
