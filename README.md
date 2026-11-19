# 探针 Probe — iOS 系统监控小面板

纯 SwiftUI 编写的 iOS 系统信息小工具，**零网络权限、零第三方依赖**，所有数据本地采集，每秒刷新。工程已配好未签名打包脚本，**可直接产出给全能签使用的 unsigned IPA**。

## 功能

- **CPU**：本进程实时占用率（环形仪表）+ 核心数
- **内存**：本进程内存占用 / 设备物理内存总量
- **磁盘**：已用 / 总容量 / 可用空间
- **电池**：电量、充电状态、低电量模式
- **温控状态**：正常 / 偏热 / 降频 / 过热
- **网络**：Wi-Fi 本机 IP
- **运行时长**：开机至今

> iOS 沙盒限制说明：App 无法读取整机 CPU/内存占用（系统不开放），所以 CPU/内存显示的是本 App 自身的占用，这是 iOS 上所有监控类 App 的共同上限，不是 bug。

## 项目结构

```
Probe/                      ← 这个文件夹直接作为 Git 仓库根目录
├── Probe.xcodeproj/        ← Xcode 工程（含共享 scheme，可命令行编译）
├── Probe/
│   ├── ProbeApp.swift      ← 入口
│   ├── ContentView.swift   ← 界面（环形仪表 + 明细卡片）
│   ├── SystemMonitor.swift ← 数据采集（mach / UIKit / Darwin）
│   ├── Info.plist
│   └── Assets.xcassets/    ← 图标（已生成）与主题色
├── build_ipa.sh            ← 一键产出未签名 IPA
├── .github/workflows/      ← 云端编译（GitHub Actions，无需 Mac）
└── README.md
```

---

# 用全能签安装（推荐路径）

全能签这类第三方签名平台，需要的是**未签名、未加密的 IPA**（签名由平台自己注入）。流程分三步：

## 第 1 步：产出未签名 IPA

### 方式 A：云端编译（没有 Mac 也能用，推荐）

> 用 GitHub 免费提供的 macOS 机器编译，公共仓库完全免费、不限时长。

**① 建仓库**

打开 https://github.com/new →
- Repository name：`probe`
- 可见性选 **Public**（免费无限时长；Private 也行，但 macOS 机器按 10 倍扣分钟数）
- 下面三个初始化选项（README / .gitignore / license）**全部不要勾**
- 点 **Create repository**

**② 把本地代码推上去**

本目录已经初始化好 git 并完成提交，只需加远程地址并推送（把 `你的用户名` 换成 GitHub 用户名）：

```bash
cd C:\Users\Administrator\WorkBuddy\2026-10-24-06-20-47\Probe
git remote add origin https://github.com/你的用户名/probe.git
git push -u origin main
```

> 首次推送会弹出浏览器让你登录 GitHub 授权，点同意即可。
> 如果建仓库时勾了 README 导致被拒，先执行 `git pull --rebase origin main` 再 push。

**③ 等它自动编译**

推送完成后打开仓库页面 → **Actions** 标签：
- 首次可能提示 "Workflows aren't being run on this repository"，点绿色按钮 **I understand my workflows, go ahead and enable them**
- 列表里出现 `build-unsigned-ipa`，黄点转圈说明正在跑，**约 3~5 分钟**
- 想手动重跑：右侧 **Run workflow** → **Run workflow**

**④ 下载 IPA**

点进那次运行（绿色 ✓）→ 页面**最下方 Artifacts** 区域 → 点 `Probe-unsigned-ipa` 下载 zip → 解压得到 **`Probe-unsigned.ipa`**。

**⑤ 进全能签**

把这个 IPA 拖进全能签签名即可（见下方第 2 步）。

### 备选：网页打不开 / 提示 "Couldn't check availability"

这个提示是 GitHub 的**仓库名可用性预检**失败，本质是 `github.com` 请求不通（不是名字被占用）。按顺序试：

1. 直接点 **Create repository**（预检失败不影响创建，多数情况能建成）
2. 换个名字，如 `probe-app-2026`
3. 无痕窗口 + 关掉广告拦截/翻译插件
4. 换网络（宽带 ↔ 手机热点），或开启代理并确认代理能访问 github.com
5. 上 GitHub 前先确认账号邮箱已验证

如果 `github.com` 完全不通、只有 API 可达，用仓库自带的脚本走 API 上传（不需要网页、不需要 git push）：

```powershell
# 1) 生成 Token：GitHub → Settings → Developer settings → Personal access tokens (classic)
#    勾选 repo 和 workflow，有效期选 7 天
# 2) 设到环境变量（不要写进文件、不要发到聊天里）
$env:GITHUB_TOKEN = "ghp_你的token"
# 3) 一键建仓 + 上传 + 构建 + 下载
python tools\push_via_api.py --repo probe --public --watch
```

产物落在 `dist/Probe-unsigned-ipa.zip`，解压即得 IPA。

> 构建失败怎么查：点进红色 ✗ 的运行 → 左侧 `编译并打包未签名 IPA` 步骤 → 展开看报错。把最后 30 行贴给我，我来改。

### 方式 B：本地 Mac 一条命令

```bash
cd Probe
chmod +x build_ipa.sh
./build_ipa.sh
# 自定义 Bundle ID（可选，全能签里也能改）：
# BUNDLE_ID=com.yourname.probe ./build_ipa.sh
```

产物：`build/Probe-unsigned.ipa`

脚本做的事：`CODE_SIGNING_ALLOWED=NO` 归档 → 删除 `_CodeSignature` 与 `embedded.mobileprovision` → 打包成 `Payload/Probe.app` 结构 → 输出 iPA。

## 第 2 步：放到全能签里签名

1. 打开全能签 → **签名** → 导入 `Probe-unsigned.ipa`
2. 选择证书（个人证书 / 企业证书，看你买的哪种）
3. 需要的话在这一步改 **App 名称、图标、Bundle ID**（全能签支持，重启后生效）
4. 点 **开始签名**，等进度完成

**关键点：**

- 如果平台提示"已签名 / 签名冲突"，说明拿到的是签过名的 IPA —— 重新用 `build_ipa.sh` 产出的那份（本工程产出的就是干净的）
- 个人证书签名要求**设备 UDID 已在描述文件里**，否则装不上（全能签一般有"添加 UDID"入口）
- 企业证书不需要 UDID，但**掉签风险高**，可能几天就失效
- 免费 Apple ID 的证书签名后 7 天失效

## 第 3 步：安装与信任

1. 签名完成后在全能签里点 **安装**（会走它自带的在线安装）
2. 首次打开若提示"未受信任的开发者"：**设置 → 通用 → VPN 与设备管理 → 选择对应证书 → 信任**
3. 打开 App，应该立刻看到环形仪表每秒跳动

---

# 备选：直接用 Xcode 装（有 Mac 的话）

1. 双击 `Probe.xcodeproj`
2. **Signing & Capabilities** → Team 选你的 Apple ID（免费账号即可），Bundle ID 改成唯一值
3. 连 iPhone，`Cmd + R`，Xcode 自动签名安装
4. 首次运行去 **设置 → 通用 → VPN 与设备管理** 信任你的证书

免费证书 7 天到期，连 Mac 重跑一次即可；想自动续签可用 AltStore / Sideloadly。

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| 全能签签名失败 | IPA 里残留签名 → 用 `build_ipa.sh` 的产物；或 Bundle ID 与证书冲突 → 改 Bundle ID |
| 装上了但点开闪退 | 证书掉了 / 描述文件不含本机 UDID / 证书已过期 → 重新签名 |
| 提示"无法安装此 App" | iOS 版本低于 15.0（工程的部署目标）→ 在 Xcode 里调低 `IPHONEOS_DEPLOYMENT_TARGET` 后重出包 |
| 图标是白块 | 全能签替换图标失败 → 保持原图标，或在平台里重新指定 1024 图标 |
| 数据不动 | 后台被系统挂起 → 切回前台会自动恢复刷新 |

## 修改建议

- 改主题：`ContentView.swift` 里的 `accentCyan / accentMint / accentAmber`
- 改刷新频率：`SystemMonitor.swift` 里 `Timer(timeInterval: 1.0, ...)`
- 改显示名：`Probe/Info.plist` 的 `CFBundleDisplayName`
- 加指标：`SystemMonitor.swift` 的 `refresh()` 里已有采集骨架，照着加即可
