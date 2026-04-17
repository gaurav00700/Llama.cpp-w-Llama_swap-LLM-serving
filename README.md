# 🚀 Llama.cpp+Llama-swap LLM serving

![Linux](https://img.shields.io/badge/platform-linux-blue)
![CUDA](https://img.shields.io/badge/CUDA-enabled-green)
![Docker](https://img.shields.io/badge/docker-ready-blue)
![systemd](https://img.shields.io/badge/systemd-timer-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## 🧠 Overview

A **fully automated local CI pipeline** for running the latest llama.cpp builds with:

* 🔁 Auto-build from GitHub
* ⚡ Incremental + cached compilation (ccache)
* 🐳 Docker serving via llama-swap
* 🔄 Smart container restart (only if binary changes)
* ⏰ Daily execution via systemd timer

---

## 🏗️ Architecture

```text
                ┌────────────────────┐
                │   GitHub (llama.cpp)│
                └─────────┬──────────┘
                          ↓
              systemd timer (daily + boot)
                          ↓
                update_build.sh
                          ↓
           Incremental build (ccache)
                          ↓
              build/bin (latest)
                          ↓
             Symlink → build_prod
                          ↓
       Docker (llama-swap container)
                          ↓
             Model serving API
```

---

## 🔁 Workflow

```text
Timer Trigger → Check Git → Build → Deploy → Restart (if needed)
```

✔ No unnecessary builds
✔ No unnecessary restarts
✔ Always up-to-date

---

## ⚡ Features

* ✅ Incremental builds (fast)
* ✅ ccache acceleration
* ✅ CUDA GPU support
* ✅ Zero unnecessary container restarts
* ✅ systemd timer (no loops)
* ✅ Clean modular design

---

## 📁 Project Structure

```bash
llama.cpp-hot-reload-stack/
│
├── scripts/
│   └── update_build.sh
│
├── systemd/
│   ├── llama_cpp-watcher.service
│   └── llama_cpp-watcher.timer
│
├── llama-swap/
│   ├── config.yaml
│   └── docker-compose.yml
│
├── llama.cpp/
│
├── docs/
│   ├── notes-llama-swap.txt
│   └── notes-llama.cpp.txt
│
├── .gitignore
└── README.md
```

---

## ⚙️ Setup Instructions

### 1. Clone repo

```bash
git clone https://github.com/YOUR_USERNAME/llama.cpp-hot-reload-stack.git
cd llama.cpp-hot-reload-stack
```

---

### 2️. Clone llama.cpp

```bash
git clone https://github.com/ggerganov/llama.cpp ~/.llm/llama.cpp
```

---

### 3. Run Llama-swap docker container

**Option 1.** Through docker compose
```bash
docker compose -f ./llama-swap/docker-compose-llama_swap.yml up -d
```

**Option 2.** Through CLI

```bash
docker run -d --runtime nvidia -p 9292:8080 \
 -v ~/.cache/huggingface/hub:/models \
 -v ~/.llm/llama-swap:/app/config \
 -v ~/.llm/llama.cpp/build/bin/llama-server:/app/llama-server \
 -v ~/.llm/llama.cpp/build/bin:/opt/llama-lib \
 --name llswap \
 ghcr.io/mostlygeek/llama-swap:cuda \
 --config /app/config/config.yaml \
 --watch-config
```

---

### 4. Install dependencies

```bash
sudo apt update
sudo apt install -y cmake build-essential ccache
```

---

### 5. Setup systemd

```bash
sudo cp systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llama_cpp-watcher.timer
```

---

## 🔍 Verification

### Check timer

```bash
systemctl list-timers | grep llama
```

---

### Check logs

```bash
journalctl -u llama_cpp-watcher.service -f
```

- After the successful start of the build script, there will be files `update_build.log`, `last_successful_run`, `llama_binary_hash` and `llama_cpp_last_hash` created at root of the repo.

---

### Test Llama-swap API

```bash
curl http://localhost:9292/v1/models
```

- Refer to [Llama-swap](https://github.com/mostlygeek/llama-swap) for more details about the [config file](https://github.com/mostlygeek/llama-swap/blob/main/docs/configuration.md)

---

## 🔄 Update Behavior

| Scenario       | Action            |
| -------------- | ----------------- |
| New commit     | Build             |
| Binary changed | Restart container |
| No change      | Do nothing        |

---

## ⚠️ Notes

* Do NOT run script as root
* CUDA must be properly installed
* Docker must support GPU (`--runtime nvidia`)
* Container restart required for new binary
* Use [Watchtower](https://github.com/nicholas-fedor/watchtower) to keep Llama-swap container updated

---

## Troubleshooting
1. ccache permission error
```bash
sudo chown -R $USER:$USER ~/.cache/ccache
```
2. YAML config error
- Check indentation
- Avoid tabs
- Quote keys with `:`

3. Refer to [notes](./docs) for other documentation
---
