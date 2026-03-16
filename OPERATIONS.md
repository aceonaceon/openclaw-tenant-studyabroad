# OpenClaw Multi-Tenant 操作手冊

> **GitHub**: https://github.com/aceonaceon/openclaw-tenant-studyabroad
> **目標環境**: Ubuntu 24 LTS VPS
> **預設模型**: Minimax M2.5

---

## 目錄

1. [系統架構總覽](#1-系統架構總覽)
2. [VPS 初始環境安裝](#2-vps-初始環境安裝)
3. [部署專案到 VPS](#3-部署專案到-vps)
4. [建立 Docker Image](#4-建立-docker-image)
5. [新增客戶（一鍵部署）](#5-新增客戶一鍵部署)
6. [設定 Caddy 反向代理](#6-設定-caddy-反向代理)
7. [批次升級所有客戶](#7-批次升級所有客戶)
8. [備份客戶資料](#8-備份客戶資料)
9. [客戶個人化設定](#9-客戶個人化設定)
10. [管理者遠端管理](#10-管理者遠端管理)
11. [安全架構說明](#11-安全架構說明)
12. [自訂 Docker Image](#12-自訂-docker-image)
13. [新增外部通訊頻道](#13-新增外部通訊頻道)
14. [故障排除](#14-故障排除)
15. [檔案結構速查](#15-檔案結構速查)

---

## 1. 系統架構總覽

### 兩層分離模型

```
母體層（Docker image 內，唯讀，你控制）
├── shared-skills/          共用技能包（所有客戶共享）
├── SOUL.md                 核心人格（每次啟動覆蓋）
├── TOOLS.md                工具說明（每次啟動覆蓋）
├── AGENTS.base.md          基礎能力（每次啟動覆蓋）
└── entrypoint.sh           啟動腳本

客戶層（bind mount，各客戶獨立）
├── USER.md                 使用者個人資料（不存在才建立）
├── MEMORY.md               對話記憶（永不覆蓋）
├── memory/                 日期記憶檔（永不覆蓋）
├── AGENTS.custom.md        客戶自訂指令（不存在才建立）
├── AGENTS.md               完整指令（每次啟動自動重組 = base + custom）
└── openclaw.json5          OpenClaw 設定（env var 引用，無明文 key）
```

### 啟動時檔案處理策略

| 檔案 | 策略 | 原因 |
|------|------|------|
| SOUL.md, TOOLS.md, AGENTS.base.md | 每次啟動覆蓋 | 確保跟 image 版本同步 |
| AGENTS.custom.md | 不存在才建立 | 保留客戶自訂內容 |
| AGENTS.md | 每次重組 | = AGENTS.base.md + AGENTS.custom.md |
| USER.md | 不存在才建立 | 保留客戶個人資料 |
| MEMORY.md, memory/ | 永不覆蓋 | 對話記憶不可丟失 |

### 網路拓撲

```
Internet
  │
  ▼
Caddy（自動 HTTPS）
  ├── client-a.example.com/webchat → 127.0.0.1:21001（只開放 /webchat）
  ├── client-b.example.com/webchat → 127.0.0.1:21002（只開放 /webchat）
  └── ...
  │
Docker containers
  ├── lobster_client-a（port 21001:18789）
  ├── lobster_client-b（port 21002:18789）
  └── ...
```

---

## 2. VPS 初始環境安裝

### 2.1 更新系統

```bash
sudo apt update && sudo apt upgrade -y
```

### 2.2 安裝 Docker

```bash
# 安裝 Docker
curl -fsSL https://get.docker.com | sh

# 將當前使用者加入 docker 群組（免 sudo）
sudo usermod -aG docker $USER

# 重新登入讓群組生效
exit
# 重新 SSH 登入後驗證
docker --version
docker compose version
```

### 2.3 安裝 Caddy

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### 2.4 安裝 Git

```bash
sudo apt install -y git
```

---

## 3. 部署專案到 VPS

### 3.1 Clone 專案

```bash
# 建立工作目錄
sudo mkdir -p /srv/lobster
sudo chown $USER:$USER /srv/lobster

# Clone 專案
cd /srv/lobster
git clone https://github.com/aceonaceon/openclaw-tenant-studyabroad.git base
```

### 3.2 確認目錄結構

```bash
ls /srv/lobster/base/
# 應看到：docker/  platform/  scripts/  skills/  templates/  .gitignore
```

### 3.3 設定腳本可執行權限

```bash
chmod +x /srv/lobster/base/scripts/*.sh
chmod +x /srv/lobster/base/docker/entrypoint.sh
```

---

## 4. 建立 Docker Image

### 4.1 首次建立

```bash
cd /srv/lobster/base
docker build -f docker/Dockerfile -t lobster-base .
```

建立完成後確認：

```bash
docker images | grep lobster-base
# 應看到 lobster-base  latest  xxxx  xx seconds ago  xxxMB
```

### 4.2 使用版本標籤（建議）

```bash
# 建議每次 build 都加日期標籤
docker build -f docker/Dockerfile -t lobster-base:2026-03-16 -t lobster-base:latest .
```

### 4.3 什麼時候需要重新 build？

- 修改了 `platform/` 下的 SOUL.md、TOOLS.md、AGENTS.base.md
- 修改了 `skills/` 下的共用技能
- 修改了 `docker/Dockerfile`（新增系統套件或 npm 套件）
- 修改了 `docker/entrypoint.sh`

**不需要重新 build 的情況**：
- 只修改客戶的 USER.md、AGENTS.custom.md、MEMORY.md（這些在 bind mount 裡）
- 只修改客戶的 .env（環境變數）

---

## 5. 新增客戶（一鍵部署）

### 5.1 基本指令

```bash
cd /srv/lobster/base
./scripts/new-tenant.sh <tenant-id> <port> <domain> [minimax-api-key]
```

### 5.2 範例

```bash
./scripts/new-tenant.sh acme-corp 21001 acme.yourlobster.com eyABCDEF12345678
```

### 5.3 執行後會做的事

1. 建立 `tenants/acme-corp/` 目錄結構
2. 生成 `.env`（含 MINIMAX_API_KEY + 自動生成的 OPENCLAW_GATEWAY_TOKEN）
3. 生成 `config/openclaw.json5`（Minimax M2.5 設定，API key 用 `${...}` 引用）
4. 複製 USER.md 和 AGENTS.custom.md 初始模板到 workspace
5. 生成 `compose.yml`
6. 修正目錄權限（uid 1000）
7. 啟動 Docker container

### 5.4 執行後輸出範例

```
[lobster] Creating tenant: acme-corp

[lobster] ✓ Tenant 'acme-corp' is running on port 21001
[lobster] Workspace: /srv/lobster/base/tenants/acme-corp/workspace/

Access:
  WebChat:  http://localhost:21001/webchat
  Domain:   https://acme.yourlobster.com/webchat (after Caddy setup)
  Token:    a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

Next steps:
  1. Edit tenants/acme-corp/workspace/USER.md with client info
  2. Edit tenants/acme-corp/workspace/AGENTS.custom.md for custom rules
  3. Add Caddy reverse proxy entry for acme.yourlobster.com
```

> **重要**：記下輸出的 Token，這是客戶登入 WebChat 用的驗證碼。

### 5.5 Port 分配建議

| 客戶 | Port | 子網域 |
|------|------|--------|
| client-a | 21001 | a.yourlobster.com |
| client-b | 21002 | b.yourlobster.com |
| client-c | 21003 | c.yourlobster.com |
| ... | 21XXX | ... |

建議從 21001 開始遞增，避免與常用 port 衝突。

---

## 6. 設定 Caddy 反向代理

### 6.1 編輯 Caddyfile

```bash
sudo nano /etc/caddy/Caddyfile
```

### 6.2 為每個客戶加入區塊

```
# 客戶: acme-corp
acme.yourlobster.com {
  # WebChat 介面（使用者可見）
  handle /webchat* {
    reverse_proxy 127.0.0.1:21001
  }
  # WebSocket（WebChat 必需）
  handle /ws* {
    reverse_proxy 127.0.0.1:21001
  }
  # 其餘全部封鎖（Gateway Control UI 等）
  handle {
    respond "403 Forbidden" 403
  }
}
```

### 6.3 重新載入 Caddy

```bash
sudo systemctl reload caddy
```

### 6.4 驗證

```bash
# 應回傳 WebChat 頁面
curl -s https://acme.yourlobster.com/webchat | head -5

# 應回傳 403 Forbidden
curl -s https://acme.yourlobster.com/
```

### 6.5 DNS 設定

在你的 DNS 供應商（如 Cloudflare）設定：

```
A    acme.yourlobster.com    → <VPS IP>
A    beta.yourlobster.com    → <VPS IP>
```

Caddy 會自動透過 Let's Encrypt 取得 HTTPS 憑證。

---

## 7. 批次升級所有客戶

### 7.1 升級流程

當你更新了 platform 模板或 skills，需要讓所有客戶吃到新版本：

```bash
cd /srv/lobster/base

# 1. 拉取最新程式碼（如果從 GitHub 管理）
git pull

# 2. 重新建立 image
docker build -f docker/Dockerfile -t lobster-base:2026-03-17 -t lobster-base:latest .

# 3. 批次重啟所有客戶
./scripts/update-all.sh
```

### 7.2 update-all.sh 做了什麼？

遍歷 `tenants/` 下每個客戶目錄，執行：
1. `docker compose pull`（如果使用 registry）
2. `docker compose up -d`（用新 image 重建 container）

重建 container 時，entrypoint.sh 會：
- 覆蓋 SOUL.md、TOOLS.md、AGENTS.base.md（吃到新版）
- 保留 USER.md、AGENTS.custom.md、MEMORY.md（客戶資料不丟）
- 重組 AGENTS.md = 新的 base + 客戶的 custom

### 7.3 升級後驗證

```bash
# 檢查所有 container 狀態
docker ps | grep lobster_

# 檢查某個客戶的 logs
docker logs lobster_acme-corp --tail 20
# 應看到 "[lobster] Workspace initialized..." 和 "[lobster] Gateway starting..."
```

---

## 8. 備份客戶資料

### 8.1 備份全部客戶

```bash
cd /srv/lobster/base
./scripts/backup.sh
```

### 8.2 備份單一客戶

```bash
./scripts/backup.sh acme-corp
```

### 8.3 備份內容

每個備份 `.tar.gz` 包含：
- `workspace/`（USER.md、MEMORY.md、AGENTS.custom.md、memory/）
- `config/openclaw.json5`
- `.env`

### 8.4 備份位置

```
/srv/lobster/base/backups/
├── acme-corp_20260316-143000.tar.gz
├── beta-inc_20260316-143000.tar.gz
└── ...
```

### 8.5 建議的自動備份

```bash
# 加入 crontab，每天凌晨 3 點自動備份
crontab -e

# 加入這行：
0 3 * * * /srv/lobster/base/scripts/backup.sh >> /srv/lobster/base/backups/backup.log 2>&1
```

---

## 9. 客戶個人化設定

### 9.1 編輯客戶個人資料（USER.md）

```bash
nano /srv/lobster/base/tenants/acme-corp/workspace/USER.md
```

填入客戶的資訊：

```markdown
# USER — 使用者個人資料

## 基本資訊
- 名稱：王大明
- 公司：ACME 留學顧問有限公司
- 職稱：行銷總監
- 所在地：台灣台北

## 偏好設定
- 語言：繁體中文
- 回應長度偏好：適中
- 溝通風格偏好：專業但友善

## 背景資訊
- 主要服務：美國大學申請、條件式入學
- 目標客群：高中生及家長
- 合作學校：XYZ University, ABC College
```

### 9.2 編輯客戶自訂指令（AGENTS.custom.md）

```bash
nano /srv/lobster/base/tenants/acme-corp/workspace/AGENTS.custom.md
```

範例：

```markdown
# AGENTS.custom — 客戶自訂能力

## 品牌設定
- 品牌名稱：ACME 留學
- 品牌語氣：溫暖、鼓勵、專業
- 禁用詞彙：某某競品名稱

## 額外指令
- 提到美國留學時，優先推薦條件式入學管道
- 社群貼文都加上 #ACME留學 #美國大學

## FAQ 快速回覆
- Q: 條件式入學是什麼？
  A: 條件式入學是指在尚未達到語言成績門檻時，先獲得大學的有條件錄取...
```

### 9.3 修改後需要重啟嗎？

| 修改內容 | 是否需要重啟 |
|----------|-------------|
| USER.md | 不需要（新 session 自動讀取） |
| AGENTS.custom.md | **需要重啟**（因為 AGENTS.md 在啟動時重組） |
| MEMORY.md | 不需要 |
| .env（API key 等） | **需要重啟** |
| openclaw.json5 | 不需要（OpenClaw 自動熱重載） |

重啟單一客戶：

```bash
cd /srv/lobster/base/tenants/acme-corp
docker compose restart
```

---

## 10. 管理者遠端管理

### 10.1 SSH Tunnel（存取 Gateway Control UI）

使用者只能透過 Caddy 存取 `/webchat`，但你作為管理者，可以透過 SSH tunnel 存取完整的 Gateway Control UI：

```bash
# 在你的本機執行
ssh -L 21001:127.0.0.1:21001 user@your-vps-ip

# 然後在本機瀏覽器開啟
# http://localhost:21001
# 即可看到完整的 Gateway Control UI
```

### 10.2 常用管理指令

```bash
# 查看所有客戶 container 狀態
docker ps | grep lobster_

# 查看某客戶的即時 logs
docker logs -f lobster_acme-corp

# 進入某客戶的 container（除錯用）
docker exec -it lobster_acme-corp /bin/bash

# 停止某客戶
cd /srv/lobster/base/tenants/acme-corp
docker compose stop

# 重啟某客戶
docker compose restart

# 完全刪除某客戶的 container（資料保留在 host）
docker compose down
```

### 10.3 查看客戶的 Gateway Token

```bash
grep OPENCLAW_GATEWAY_TOKEN /srv/lobster/base/tenants/acme-corp/.env
```

### 10.4 更換客戶的 API Key

```bash
# 編輯 .env
nano /srv/lobster/base/tenants/acme-corp/.env
# 修改 MINIMAX_API_KEY=新的key

# 重啟讓新 key 生效
cd /srv/lobster/base/tenants/acme-corp
docker compose restart
```

---

## 11. 安全架構說明

### 11.1 三層防護

```
Layer 1 — 網路層（Caddy）
  使用者只能存取 /webchat 和 /ws
  Gateway Control UI、settings 等全部回 403
  管理者透過 localhost 直連

Layer 2 — 設定檔層
  openclaw.json5 中 API key 只有 "${MINIMAX_API_KEY}" 佔位符
  容器內不存在任何含明文 key 的 .env 檔案

Layer 3 — Process 層
  API key 只存在於 Docker 注入的 process 環境變數中
  Agent 無法透過讀檔取得 key
```

### 11.2 API Key 流向

```
Host: tenants/client-a/.env          （明文 key，只在 host 端）
  ↓ Docker compose env_file
Container: process environment       （記憶體中，不落地為檔案）
  ↓ OpenClaw 解析 "${MINIMAX_API_KEY}"
openclaw.json5: "${MINIMAX_API_KEY}" （只有佔位符，無明文）
```

### 11.3 各角色能看到什麼？

| 內容 | 使用者（WebChat） | Agent | 管理者（SSH） |
|------|-------------------|-------|--------------|
| WebChat 對話 | ✓ | ✓ | ✓ |
| Gateway Control UI | ✗ | — | ✓ |
| USER.md 內容 | 透過 Agent | ✓ | ✓ |
| AGENTS.md 內容 | 透過 Agent | ✓ | ✓ |
| API Key 明文 | ✗ | ✗ | ✓（.env） |
| openclaw.json5 | 看到 "${...}" | 看到 "${...}" | ✓ |

---

## 12. 自訂 Docker Image

### 12.1 新增系統套件（apt-get）

編輯 `docker/Dockerfile`，在 System packages 區塊加入：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    imagemagick \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*
```

### 12.2 新增 npm 全域套件

編輯 `docker/Dockerfile`，取消註解並加入：

```dockerfile
RUN npm install -g sharp puppeteer
```

### 12.3 新增共用技能（Skills）

```bash
# 建立技能目錄
mkdir -p /srv/lobster/base/skills/my-new-skill/

# 加入技能檔案（依 OpenClaw skill 格式）
# ...

# 重新 build image
cd /srv/lobster/base
docker build -f docker/Dockerfile -t lobster-base .

# 推送到所有客戶
./scripts/update-all.sh
```

### 12.4 修改平台模板

```bash
# 修改核心人格
nano /srv/lobster/base/platform/SOUL.md

# 修改基礎能力
nano /srv/lobster/base/platform/AGENTS.base.md

# 修改工具說明
nano /srv/lobster/base/platform/TOOLS.md

# 重新 build 並推送
cd /srv/lobster/base
docker build -f docker/Dockerfile -t lobster-base .
./scripts/update-all.sh
```

---

## 13. 新增外部通訊頻道

### 13.1 Telegram

```bash
# 1. 在 BotFather 建立 bot，取得 token

# 2. 編輯客戶 .env，加入 token
nano /srv/lobster/base/tenants/acme-corp/.env
# 加入：TELEGRAM_BOT_TOKEN=123456:ABC-xxx

# 3. 編輯 openclaw.json5，加入 channels 區塊
nano /srv/lobster/base/tenants/acme-corp/config/openclaw.json5
# 在 skills 區塊後加入：
# channels: {
#   telegram: {
#     botToken: "${TELEGRAM_BOT_TOKEN}",
#     allowedChatIds: [123456789]
#   }
# }

# 4. 更新 compose.yml 加入環境變數
# environment 區塊加入：
#   - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}

# 5. 重啟
cd /srv/lobster/base/tenants/acme-corp
docker compose restart
```

### 13.2 Discord

流程類似 Telegram，需要：
- 在 Discord Developer Portal 建立 Application 和 Bot
- 取得 Bot Token 和 Guild/Channel ID
- 加入 .env 和 openclaw.json5

### 13.3 LINE

流程類似，需要：
- 在 LINE Developers Console 建立 Messaging API Channel
- 取得 Channel Access Token 和 Channel Secret
- 加入 .env 和 openclaw.json5

---

## 14. 故障排除

### 14.1 Container 無法啟動

```bash
# 查看錯誤訊息
docker logs lobster_acme-corp

# 常見原因：
# 1. Port 已被佔用 → 改用其他 port
# 2. 權限問題 → chown -R 1000:1000 tenants/acme-corp/
# 3. Image 不存在 → docker build -f docker/Dockerfile -t lobster-base .
```

### 14.2 WebChat 無法連線

```bash
# 1. 確認 container 在跑
docker ps | grep lobster_acme-corp

# 2. 確認 port 有開
curl http://localhost:21001/webchat

# 3. 確認 Caddy 設定
sudo systemctl status caddy
cat /etc/caddy/Caddyfile | grep acme

# 4. 確認 DNS 解析
dig acme.yourlobster.com
```

### 14.3 Agent 回覆錯誤或不回覆

```bash
# 查看 container logs
docker logs lobster_acme-corp --tail 50

# 如果看到 "MINIMAX_API_KEY is not set"
# → 檢查 .env 中的 MINIMAX_API_KEY
grep MINIMAX_API_KEY /srv/lobster/base/tenants/acme-corp/.env

# 如果 API key 有設但還是不行
# → 確認 key 有效（到 MiniMax 後台檢查）
```

### 14.4 升級後客戶資料不見

**不應該發生**，因為客戶資料在 bind mount 中，container 重建不影響。

但如果真的發生：
```bash
# 從備份還原
cd /srv/lobster/base/backups
tar -xzf acme-corp_20260316-143000.tar.gz -C /srv/lobster/base/tenants/acme-corp/
```

### 14.5 權限錯誤（EACCES）

```bash
# OpenClaw 容器使用 node user (uid 1000)
# 如果 host 端資料夾權限不對，會噴 EACCES
sudo chown -R 1000:1000 /srv/lobster/base/tenants/acme-corp/config
sudo chown -R 1000:1000 /srv/lobster/base/tenants/acme-corp/workspace
```

---

## 15. 檔案結構速查

### 專案結構（/srv/lobster/base/）

```
base/
├── docker/
│   ├── Dockerfile              ← Docker image 定義
│   └── entrypoint.sh           ← 容器啟動腳本
├── platform/
│   ├── SOUL.md                 ← 核心人格（固定，每次啟動覆蓋）
│   ├── TOOLS.md                ← 工具說明（固定）
│   ├── AGENTS.base.md          ← 基礎能力（固定）
│   ├── AGENTS.custom.example.md← 客戶自訂範本
│   └── USER.example.md         ← 使用者資料範本
├── scripts/
│   ├── new-tenant.sh           ← 一鍵新增客戶
│   ├── update-all.sh           ← 批次升級
│   └── backup.sh               ← 備份
├── skills/
│   ├── README.md               ← 技能說明
│   └── (skill directories)     ← 共用技能
├── templates/
│   ├── compose.yml             ← Compose 模板（參考用）
│   ├── Caddyfile.example       ← Caddy 模板（參考用）
│   └── env.example             ← 環境變數模板（參考用）
├── tenants/                    ← 客戶資料（git ignored）
│   └── acme-corp/
│       ├── .env                ← 環境變數（含 API key 明文）
│       ├── compose.yml         ← Docker Compose 設定
│       ├── config/
│       │   └── openclaw.json5  ← OpenClaw 設定（${...} 引用）
│       └── workspace/
│           ├── USER.md         ← 客戶個人資料
│           ├── MEMORY.md       ← 對話記憶
│           ├── AGENTS.custom.md← 客戶自訂指令
│           ├── AGENTS.md       ← 完整指令（自動生成）
│           ├── AGENTS.base.md  ← 基礎能力（從 image 複製）
│           ├── SOUL.md         ← 核心人格（從 image 複製）
│           ├── TOOLS.md        ← 工具說明（從 image 複製）
│           └── memory/         ← 日期記憶檔
├── backups/                    ← 備份檔案
└── .gitignore
```

### 常用指令速查

| 動作 | 指令 |
|------|------|
| 新增客戶 | `./scripts/new-tenant.sh <id> <port> <domain> [api-key]` |
| 升級所有客戶 | `./scripts/update-all.sh` |
| 備份所有客戶 | `./scripts/backup.sh` |
| 備份單一客戶 | `./scripts/backup.sh <tenant-id>` |
| 重建 image | `docker build -f docker/Dockerfile -t lobster-base .` |
| 重啟單一客戶 | `cd tenants/<id> && docker compose restart` |
| 查看客戶 logs | `docker logs lobster_<id> --tail 50` |
| 進入客戶容器 | `docker exec -it lobster_<id> /bin/bash` |
| 查看所有容器 | `docker ps \| grep lobster_` |
| 查看 Gateway Token | `grep OPENCLAW_GATEWAY_TOKEN tenants/<id>/.env` |
| SSH Tunnel 管理 | `ssh -L <port>:127.0.0.1:<port> user@vps` |
