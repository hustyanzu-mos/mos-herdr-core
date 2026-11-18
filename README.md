# HerdrCore MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[Herdr Core](https://herdr.dev)（`hc`）的插件实现仓库。

- Hub 索引条目在：[hustyanzu/mos-templates](https://github.com/hustyanzu/mos-templates)
- 本仓库只负责插件实现和 release `.deb`

---

## 它做什么

- 从官方发布源 `https://releases.herdr.dev` 下载 `herdr-core`（支持 `amd64` / `arm64`）
- 把二进制、配置、状态持久化到 `/boot/optional/plugins/herdr-core`
- 不依赖 systemd：用 `setsid` 启动 headless core，并记录 PID
- 通过 **Unix socket + SSH** 使用，不开放 TCP 端口
- 在 MOS 启动完成后按设置自动启动
- 提供 MOS 插件页面：安装 / 更新 / 启动 / 停止 / 重启 / 状态 / 日志 / 设置

Herdr Core 的终端、agent 和文件操作都留在 NAS 上；你从工作站通过 SSH 连接。

---

## 设计要点（为什么不是普通 Docker 容器）

MOS 的系统盘是只读 rootfs，重启后 `/usr`、`/var`、`/root` 都会重建。因此：

| 内容 | 位置 | 是否持久 |
| --- | --- | --- |
| `herdr-core` 二进制（持久副本） | `/boot/optional/plugins/herdr-core/bin/` | ✅ |
| `herdr-core` 运行时副本 | `/usr/bin/herdr-core.real`（启动时从 `/boot` 复制） | ❌（RAM，重启恢复） |
| `config.toml`、templates | `/boot/optional/plugins/herdr-core/config/herdr-core/` | ✅ |
| 终端状态 `terminals.json`、core 日志 | `/boot/optional/plugins/herdr-core/state/herdr-core/` | ✅ |
| 运行时 socket | `/run/herdr-core/hc.sock` | ❌（tmpfs，重启重建） |
| `/usr/bin/hc` 包装脚本 | `.deb` 安装 + `functions` 启动时恢复 | 每次启动恢复 |

- 不使用 systemd：MOS 是 Devuan，`hc server start` 在没有 systemd user manager 时会退化为普通进程；插件直接用 `setsid herdr-core serve`，行为可控。
- `/boot` 可能挂载为 `noexec`：插件把二进制持久化在 `/boot`，但实际从 `/usr/bin/herdr-core.real` 运行；每次启动由 `functions` 恢复这个 RAM 副本。
- 以 **root** 运行：与 MOS 的 SSH / OpenCode 插件一致。socket 为 root 所有，只有能 SSH 登录 root 的人可以连接。
- 只监听 Unix socket：远程访问走 SSH，不额外暴露端口。

---

## 持久化

MOS 的 Hub 安装器会把 `.deb` 和 `functions` 放到：

```text
/boot/optional/plugins/herdr-core/<version>/
```

并在插件根目录写 `template.json`。启动时 `installplugins-mos` 会重新安装该
`.deb`，`mos_start`/`mos_start_after_services` 会恢复运行时并启动 core。

- 二进制：`/boot/optional/plugins/herdr-core/bin/herdr-core`
- 配置：`/boot/optional/plugins/herdr-core/config/herdr-core/`
- 状态：`/boot/optional/plugins/herdr-core/state/herdr-core/`
- 运行时：`/usr/bin/herdr-core.real`、`/run/herdr-core/`（RAM，启动时恢复）

如果手动 `dpkg -i`，插件只对当前运行有效；要让它重启后仍然存在，请使用
MOS Hub，或把 `.deb`/`functions` 放到版本目录并补上 `template.json`。

---

## 仓库结构

```text
mos-herdr-core/
├── functions                       # MOS 生命周期钩子
├── settings.json                   # 插件默认设置
├── herdr-core-backend              # /usr/bin/plugins/herdr-core
├── herdr-core-wrapper              # /usr/bin/hc
├── images/
│   └── herdr-core.png              # 插件页面图标
├── page/                           # Vue 插件页面
├── build.sh                        # 本地构建 .deb
└── .github/workflows/
    └── build-plugin.yml            # GitHub Release 自动构建
```

Hub 索引条目（`plugins/herdr-core.json`）和维护者信息在
[mos-templates](https://github.com/hustyanzu/mos-templates) 仓库，不在本仓库重复。

---

## 构建

需要 Node.js 20+、`ar`、`tar`、`gzip`；如果系统有 `dpkg-deb` 会优先使用。

```bash
./build.sh 0.1.0
```

输出：

```text
build/herdr-core-0.1.0-1+mos-plugin_all.deb
build/herdr-core-0.1.0-1+mos-plugin_all.deb.md5
```

页面单独开发：

```bash
cd page
npm install
npm run dev
```

---

## 发布

实现仓库需要产生 `.deb` release，索引条目的 `repository` 会指向这里：

```bash
git tag 0.1.0
git push origin 0.1.0
```

GitHub Actions 会构建 `.deb` + `.md5` 并创建 Release。

然后在 MOS 添加索引仓库：

**Settings → System Configuration → MOS Hub Settings → Add Repository**

```text
https://github.com/hustyanzu/mos-templates
```

Refresh 后到 **Docker → MOS Hub → Plugins** 安装 **HerdrCore**。

> 私有仓库：在 MOS 配置 GitHub Token 后，Hub 会用 token 拉取本仓库的 release `.deb`。
> Herdr Core 二进制仍从公开的 `releases.herdr.dev` 下载，不依赖 GitHub token。

> 不要直接把本实现仓库添加到 MOS Hub；索引在 `mos-templates`。
> 如果你偏要单仓库自包含，也可以把 `mos-templates/plugins/herdr-core.json` 复制回本仓库，
> 但多插件时建议保持现在的拆分。

---

## 本地/手动安装（不经过 Hub）

把 `.deb` 拷到 MOS 后：

```bash
dpkg -i herdr-core-0.1.0-1+mos-plugin_all.deb
```

然后打开 **Plugins → Herdr Core**，点击 **Install**（下载 `herdr-core` 二进制），再点击 **Start**。

也可以直接命令行：

```bash
/usr/bin/plugins/herdr-core install_binary
/usr/bin/plugins/herdr-core start
/usr/bin/plugins/herdr-core status
```

首次启动时如果设置了 `auto_start`，MOS 下次启动会自动拉起。

---

## 使用

1. 在 MOS 打开 **Settings → Network Services → SSH**（如果还没开）。
2. 从工作站执行：

   ```bash
   ssh root@<NAS-IP> hc ls
   ```

   或把 NAS 加为 Herdr 机器：

   ```bash
   hc machine add <NAS-IP>
   hc machine ls
   hc run --on <NAS-IP> --bg bash
   ```

3. Herdr Core 的配置在：

   ```text
   /boot/optional/plugins/herdr-core/config/herdr-core/config.toml
   ```

   templates 在：

   ```text
   /boot/optional/plugins/herdr-core/config/herdr-core/templates/
   ```

   编辑后可以用插件页的 **Restart** 让 core 重新读取。

---

## 与 `hc machine add` / `hc machine update` 的关系

`hc machine add` 会先通过 SSH 检查远端的 `hc`。如果远端没有 `hc` 或版本太旧，
它会询问是否把本机的 `hc` 复制过去（加 `--install` 则不询问）：

```text
Copy this hc (0.1.21) there? [Y/n]
```

- 插件已经把 `/usr/bin/hc` 和 `/usr/bin/herdr-core` 设为受管理的包装脚本；
  正常情况回答 **No** 即可，`hc connect` 会使用插件启动的 core。
- 如果允许复制，它会写到远端的 `~/.local/bin/herdr-core`（不是 `/usr/bin`，
  不会覆盖插件的二进制）。这是一个**不受插件管理**的副本。
- `hc machine update` 明确会“复制本机 hc 到远端并重启”，可能用默认路径
  （`~/.config/herdr-core`、默认 socket）启动第二个 core。不要用它更新 NAS；
  请在插件页点 **Update**，它更新持久化二进制并重启插件 core。
- 如果已经让客户端复制过，检查并清理：

  ```bash
  ssh root@<NAS-IP> '
    command -v hc; command -v herdr-core;
    ls -l ~/.local/bin/herdr-core ~/.local/bin/hc 2>/dev/null || true;
    ps -ef | grep herdr-core | grep -v grep
  '
  ```

  受管理的 core 进程是 `/usr/bin/herdr-core.real serve`。如果看到
  `~/.local/bin/herdr-core serve`，那是客户端复制出来的第二份，可以清理：

  ```bash
  pkill -f "$HOME/.local/bin/herdr-core serve"
  rm -f ~/.local/bin/herdr-core ~/.local/bin/hc
  ```

- 建议工作站和 NAS 的 hc 都保持最新：工作站用 `hc update`，NAS 用插件页
  **Check updates** → **Update**。这样 `hc machine add` 不会提示版本过旧。
- `hc machine ls` 可能提示远端“stops at logout”；插件的 core 是 `setsid`
  启动的，不依赖 SSH 登录会话，不受该提示影响。

---

## 插件设置

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `auto_start` | `true` | MOS 服务启动后自动启动 core |
| `auto_install` | `true` | 二进制缺失时自动下载 |
| `pin_version` | `""` | 固定 Herdr Core 版本，例如 `0.1.21`；空为最新 |
| `work_dir` | `""` | 新终端默认目录；空或不存在则用 `/` |
| `version` | `""` | 已安装版本，由插件自动维护 |

设置也可以在 MOS 插件页面修改。

---

## 升级 / 卸载

**升级**：插件页点击 **Check updates** → **Update**。
后端会停止 core、校验 sha256、替换二进制、恢复运行。

**卸载**：在 MOS 插件页卸载插件。持久化数据会保留在
`/boot/optional/plugins/herdr-core`，需要时手动删除。

不要直接在 MOS 上运行 `hc update`：它会绕过插件的版本记录和包装脚本。
请使用插件页的 Update。

---

## 排错

- 看状态：

  ```bash
  /usr/bin/plugins/herdr-core status
  ```

- 看日志：

  ```bash
  /usr/bin/plugins/herdr-core logs
  tail -n 100 /boot/optional/plugins/herdr-core/core.log
  tail -n 100 /boot/optional/plugins/herdr-core/state/herdr-core/default/core.log
  ```

- 手动下载/重装：

  ```bash
  /usr/bin/plugins/herdr-core install_binary
  ```

- 确认架构：

  ```bash
  uname -m        # x86_64 或 aarch64
  ```

- `hc: command not found`：确认 `/usr/bin/hc` 存在；插件的 `mos_start` 会恢复它。

- SSH 连不上：先确认 MOS 的 SSH 服务已开启，并且 root 登录可用。

---

## 安全说明

- Herdr Core 以 root 运行，拥有与 root SSH 相同的权限。
- 只通过 Unix socket 通信，远程依赖 SSH。请不要把 socket 暴露到网络。
- 插件的 WebUI 操作走 MOS 的登录认证；不要给不可信用户 MOS 管理员权限。

---

## 许可证

本仓库的插件代码（脚本、Vue 页面、构建配置）使用 MIT License。
`herdr-core` 二进制由官方 `releases.herdr.dev` 下载，遵循其上游许可。