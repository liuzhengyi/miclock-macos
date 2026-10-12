# 3.2.2 · build 14（2026-10-12）

- 菜单正常状态缩减为当前输入和状态两行；配置麦克风、自动锁定、设置、语音输入法推荐、使用入门和问题反馈保留一级入口。异常时仍显示锁定目标与监听提示。
- 临时切换输入、登录启动及系统批准、分享、更新记录、检查更新、诊断、关于和卸载移入“更多”。临时切换仍暂停锁定；配置目标保留既有开关状态；快捷键和关闭窗口继续运行的行为保留。
- 新增“语音输入法推荐”网页入口，设置窗口和使用引导明确麦克风配置与语音识别各自的用途。
- 中英文菜单和操作按钮去除末尾省略号，发送中的进度文案保留。
- 新增生产菜单层级、动作保留、设备勾选、登录批准、更新可用性、推荐网页地址及本地化回归；真实菜单操作与新页面发布由本轮发行验收记录确认。

---

# 3.2.1 · build 13（2026-10-12）

- 修复顶部图标落在屏幕刘海遮挡区域的问题：启动时只检查并修复 MicLock 自身的无效菜单栏位置记录，保留有效的用户位置。
- 重复激活时复用同一个菜单栏入口；按钮图像丢失时重新绘制，并在分配正常尺寸前设置稳定身份。
- 关闭设置窗口后继续运行，点击顶部图标可直接配置锁定目标、临时切换输入和打开设置。
- 新增 32 项菜单栏模型与绘制回归；完整原生自动测试通过。本机 macOS 26.6.2 实测普通启动可见、鼠标点击展开、菜单配置目标及恢复、关闭窗口后同一进程继续运行，以及连续 3 次普通重启无重复图标。
- 额外的虚拟输入强制扰动未能建立测试前提，不能据此确认真实硬件的输入恢复；其他 macOS 版本和 Intel 实机仍待验收。
- 当前仍为 ad-hoc 签名，Developer ID、Apple 公证、清洁安装、真实升级和卸载验收仍待完成。

---

# 3.2.0 · build 12（2026-10-11）

- 菜单栏图标明确保持可见、禁止拖出移除；关闭设置窗口后继续运行，直接打开和再次打开应用显示设置。登录启动保持安静。
- 配置、临时切换、自动锁定、暂停、登录启动均保持原生菜单快捷入口。
- 加入 Sparkle 2.10.0 的用户主动检查更新流程，独立 Ed25519 签名校验更新归档和 appcast，确认后安装并重启；不默认后台检查、下载或发送系统画像。
- 应用内查看本地版本记录，并增加卸载入口；只处理当前安装在 Applications 的自身 app、自身登录项以及精确白名单的设置文件，未识别文件保留。
- 应用内问题反馈，附带可预览的脱敏诊断；失败草稿和幂等回执由用户主动重试。
- 标准 DMG 根目录提供 MicLock.app、Applications 链接与拖入安装图示，不包含命令脚本和额外包装目录。
- 自动回归新增菜单动作图、卸载路径/符号链接边界、更新地址信任边界和反馈模型测试。隔离测试不代替真实安装、升级重启、卸载和硬件验收。
- 可选匿名使用统计默认关闭，只在主动开启后发送随机编号和固定事件；正常锁定按 UTC 每日最多一次，经成功回执才标记，关闭后取消待发任务并清除随机编号。
- 当前应用仍为 ad-hoc 签名。正式 Developer ID 签名、公证、Gatekeeper 和清洁安装验收仍待完成。

---

# 3.1.2 发行准备 · build 11（2026-10-11）

未正式签名、公证、安装或发布。

- “报告问题”改为已验收的个人飞书匿名反馈表单，保留用户主动复制、粘贴脱敏诊断的方式，不自动采集上传。
- “下载与更新说明”和中英文分享文案改为实际产品官网，避免把用户导向历史社区版本。
- 中英文安装文档采用拖入 Applications 的流程，并明确官网发布包与 GitHub 社区 2.1.1 源码的区别。
- 新增 `show-menu`：必要时启动 MicLock，通知实际运行进程打开原生菜单栏菜单；不修改自动锁定开关或构造展示状态。
- 新增正式产品“状态与设置…”窗口：真实当前麦克风、健康、目标选择与自动锁定控制，复用已有配置和音频逻辑；设备事件驱动更新，不增加轮询。不可用目标保留占位，配置写失败时下拉恢复到实际保存目标。关闭窗口不退出应用，再次打开应用可重新显示窗口。
- 新增 `show-status` 打开上述真实窗口，与 `show-menu` 共用进程定向请求及确认机制。
- 正式发行仍需 Developer ID Application 签名、Apple 公证、Gatekeeper 与安装验收；未通过时保留正式发行门禁。

---

# 3.1.1 本地预览 · build 10（2026-10-11）

未正式发布或安装。

- 修复冲突退避到期没有自动恢复纠正的问题，使用单调时间和到期重试 timer。
- 配置读取不再隐式迁移/写入；配置变更和自动纠正共享事务锁，避免暂停确认后仍被旧纠正覆盖。
- 配置按字段原子合并，保留并发更新；非法字段默认关闭锁定。
- 设备事件监听注册失败时显示提示，每 5 秒恢复检查，成功后撤销兜底 timer。
- 首次新装锁定默认关闭；源码安装脚本升级时保留既有选择。
- 引导与分享文案改为具体痛点；退出文案明确停止锁定；旧健康快照不再表示运行中的正常锁定。
- 使用引导独立为 MLGuide，纠正策略独立为 MLCorrectionPolicy；新增只读引导展示入口 --guide。
- 增加设备、策略、隔离并发状态及假设备 timer/监听回归测试。

---

# Changelog

## 3.1.0

- Center status badge glyphs by their visible outline, with padding in increased contrast mode.
- Add a one-time localized quick start, sharing text copy, and release notes link.
- Clarify input-routing scope, privacy and feedback steps.


## 3.0.0 - 2026-07-13

- Replaced SwitchAudioSource polling with native, event-driven CoreAudio.
- Persisted devices by stable UID and added name-to-UID migration.
- Merged enforcement and menu state into one native app process.
- Added real health states, conflict backoff, atomic configuration, and redacted diagnostics.
- Separated one-time switching from persistent lock-target selection.
- Added English and Simplified Chinese localization and accessibility improvements.
- Added a universal macOS 13+ build with no downloaded executable dependency.
- Added transactional install rollback, ownership-aware CLI aliases, and safe uninstall paths.
- Added CI, static validation, package tests, and release verification.

## 2.1.1 - 2026-07-10

- Added a native AppKit menu-bar interface.
- Added colored badges for built-in, Bluetooth, other, and unavailable inputs.
- Changed the microphone body to a macOS template image for native contrast.
- Bundled Apple Silicon SwitchAudioSource 1.2.2 and its license in DMG releases.
- Added command aliases for status, selection, pause, resume, and logs.
- Added a one-step DMG installer and uninstaller.

## 1.0.0

- Initial LaunchAgent and command-line implementation.
