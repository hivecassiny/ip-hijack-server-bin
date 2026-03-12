# IP Hijack Server — 预编译发行版

IP Hijack 管理服务器。接收并管理多台路由器 Agent 的加密连接，提供 Web 管理界面进行实时连接监控、IP 劫持操作和多用户权限管理。

> 源码仓库：[hivecassiny/ip-hijack](https://github.com/hivecassiny/ip-hijack)  
> Agent 发行版：[hivecassiny/ip-hijack-bin](https://github.com/hivecassiny/ip-hijack-bin)

---

## 架构概览

```
┌──────────────┐       ┌──────────────────┐       ┌──────────────┐
│   路由器 A    │       │    Server        │       │   路由器 B    │
│  (Agent)     │◄─────►│  (本仓库)        │◄─────►│  (Agent)     │
│  linux/mips  │  加密  │                  │  加密  │  linux/arm64 │
└──────────────┘  TCP  │  TCP  :9000      │  TCP  └──────────────┘
                       │  HTTP :8080      │
                       └──────┬───────────┘
                              │ HTTP
                       ┌──────┴──────┐
                       │  管理员浏览器  │
                       │  Web 管理面板  │
                       └─────────────┘
```

---

## Server 功能

| 功能 | 说明 |
|------|------|
| **Web 管理面板** | 可视化查看所有 Agent、连接列表、劫持规则 |
| **实时连接监控** | Agent 每 5 秒上报，面板即时展示所有外部连接 |
| **一键 IP 劫持** | 选中目标 IP → 填入转发地址 → 立即下发到 Agent 执行 |
| **多用户权限** | admin / control / readonly 三级权限，支持子账号 |
| **子账号分配** | 管理员可创建子账号并分配特定 Agent，子账号只看到自己的设备 |
| **端到端加密** | 使用 [umbra](https://github.com/hivecassiny/umbra) 加密（ECDH + ChaCha20-Poly1305） |
| **Zstd 压缩** | Agent 通信默认开启压缩，节省带宽 |
| **SQLite 持久化** | 用户、Agent、劫持规则全部存入数据库，重启不丢失 |
| **规则自动恢复** | Agent 重连后 Server 自动下发之前的劫持规则 |

---

## 预编译二进制

| 平台 | 文件 | 说明 |
|------|------|------|
| linux/amd64 | `server-linux-amd64` | 云服务器、x86 主机 |
| linux/arm64 | `server-linux-arm64` | ARM 云服务器、树莓派 4/5 |
| linux/arm | `server-linux-arm` | 树莓派 2/3、旧 ARM 设备 |
| darwin/amd64 | `server-darwin-amd64` | macOS Intel（调试用） |
| darwin/arm64 | `server-darwin-arm64` | macOS Apple Silicon（调试用） |

> 不提供 mips/mipsle 版本（SQLite 依赖限制）。Server 通常部署在云服务器上，不需要 mips。

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/hivecassiny/ip-hijack-server-bin/main/install.sh | sudo bash
```

交互式菜单：

```
  ╔══════════════════════════════════════════╗
  ║       IP Hijack Server Installer         ║
  ║                  v1.0.0                   ║
  ╚══════════════════════════════════════════╝

  [✓] Detected platform: linux-amd64

  Select an option:

    1)  Install Server
    2)  Update Server
    3)  Uninstall Server
    4)  Show Status
    0)  Exit
```

### 安装流程（选择 1）

脚本会交互式询问：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| TCP listen address | `:9000` | Agent 连入端口 |
| HTTP listen address | `:8080` | Web UI 端口 |
| Admin password | `admin` | 管理员密码（**务必修改**） |
| Database path | `/var/lib/ip-hijack/hijack.db` | SQLite 数据库 |
| Compression | `Y` | Zstd 压缩 |

安装完成后自动创建 systemd 服务并启动，直接访问 `http://<server-ip>:8080` 即可。

### 直接命令

```bash
sudo ./install.sh install      # 安装
sudo ./install.sh update       # 更新
sudo ./install.sh uninstall    # 卸载
./install.sh status            # 状态
```

---

## 手动安装

### 1. 下载

```bash
wget https://raw.githubusercontent.com/hivecassiny/ip-hijack-server-bin/main/bin/server-linux-amd64
chmod +x server-linux-amd64
sudo mv server-linux-amd64 /usr/local/bin/ip-hijack-server
```

### 2. 运行

```bash
ip-hijack-server \
  -tcp :9000 \
  -http :8080 \
  -db /var/lib/ip-hijack/hijack.db \
  -admin-pass YourSecurePassword
```

### 3. 配置 systemd（推荐）

```bash
sudo mkdir -p /var/lib/ip-hijack

sudo tee /etc/systemd/system/ip-hijack-server.service > /dev/null <<EOF
[Unit]
Description=IP Hijack Management Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ip-hijack-server -tcp :9000 -http :8080 -db /var/lib/ip-hijack/hijack.db -admin-pass YourSecurePassword
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ip-hijack-server
```

### 4. 管理

```bash
sudo systemctl status ip-hijack-server       # 状态
sudo journalctl -u ip-hijack-server -f       # 实时日志
sudo systemctl restart ip-hijack-server      # 重启
sudo systemctl stop ip-hijack-server         # 停止
```

---

## 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-tcp` | `:9000` | Agent TCP 监听地址 |
| `-http` | `:8080` | Web UI HTTP 监听地址 |
| `-db` | `hijack.db` | SQLite 数据库路径 |
| `-admin-pass` | `admin` | 管理员密码（首次运行设置） |
| `-compress` | `true` | 启用 Zstd 压缩 |

---

## 快速部署流程

### Step 1: 在云服务器上安装 Server

```bash
curl -fsSL https://raw.githubusercontent.com/hivecassiny/ip-hijack-server-bin/main/install.sh | sudo bash
# 选择 1) Install Server
# 设置强密码
```

### Step 2: 开放防火墙端口

```bash
# 放行 Agent TCP 端口和 Web UI 端口
sudo ufw allow 9000/tcp    # Agent 连入
sudo ufw allow 8080/tcp    # Web UI

# 或 iptables
sudo iptables -A INPUT -p tcp --dport 9000 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
```

### Step 3: 在路由器上安装 Agent

```bash
curl -fsSL https://raw.githubusercontent.com/hivecassiny/ip-hijack-bin/main/install.sh | sudo bash
# 选择 1) Install Agent
# 输入 Server 地址，如 203.0.113.50:9000
```

### Step 4: 登录 Web 管理面板

浏览器打开 `http://<server-ip>:8080`，管理员登录后可以：

- 查看所有已连接的 Agent
- 实时浏览每个 Agent 的外部连接列表
- 选中目标 IP 执行劫持（DNAT 转发）
- 创建子账号并分配 Agent

---

## Web 管理面板功能

### 用户权限

| 角色 | 查看连接 | 执行劫持 | 管理用户 | 分配 Agent |
|------|---------|---------|---------|-----------|
| admin | ✅ | ✅ | ✅ | ✅ |
| control | ✅ | ✅ | ❌ | ❌ |
| readonly | ✅ | ❌ | ❌ | ❌ |

### 子账号

管理员可以：
1. 创建子账号并设置角色（control / readonly）
2. 将特定 Agent 分配给子账号
3. 子账号登录后只能看到被分配的 Agent
4. 每个子账号有独立的登录路径：`/u/<username>`

---

## 常见问题

### Agent 连不上 Server？

1. Server 是否在运行：`systemctl status ip-hijack-server`
2. 防火墙是否放行了 9000 端口
3. Server 日志：`journalctl -u ip-hijack-server -f`
4. Agent 会无限重试，Server 恢复后自动连接

### Web UI 打不开？

1. 检查 8080 端口是否放行
2. 检查是否有其他服务占用该端口：`ss -tlnp | grep 8080`
3. 尝试换端口：修改 systemd 配置中的 `-http` 参数

### 如何备份数据？

```bash
# 备份数据库
cp /var/lib/ip-hijack/hijack.db /backup/hijack.db.bak

# 恢复
cp /backup/hijack.db.bak /var/lib/ip-hijack/hijack.db
sudo systemctl restart ip-hijack-server
```

### 忘记管理员密码？

停止服务后用新密码重启，会重置 admin 密码：

```bash
sudo systemctl stop ip-hijack-server
# 编辑 service 文件中的 -admin-pass 参数
sudo systemctl daemon-reload
sudo systemctl start ip-hijack-server
```

---

## 许可

[MIT License](https://github.com/hivecassiny/ip-hijack/blob/main/LICENSE)
