# MicLock：macOS 全局麦克风锁定
> 源码版本：3.2.0，build 12。Developer ID 签名、Apple 公证和更广泛的真实设备验收仍需完成。

<p align="center">
  <img src="docs/MicLock-icon.png" width="160" alt="MicLock 图标">
</p>

[English](README.md)

**戴上耳机后，语音输入变差？先检查麦克风是否被切换。** MicLock 把 macOS 系统默认输入保持在你配置的麦克风，适合佩戴耳机进行 AI 对话、语音写作和会议的 Mac 用户。

## 三步开始

1. 安装并打开 MicLock，点击菜单栏麦克风图标。
2. 在“设置锁定目标”中配置电脑自带麦克风，确认“自动锁定”开启。
3. 在语音软件中把输入选成“系统默认”，耳机仍可负责输出。

首次直接打开会显示状态与设置；菜单栏可快捷配置麦克风、暂停锁定、反馈、查看版本记录、检查更新和卸载。

点击菜单中的“状态与设置…”可查看真实当前麦克风、锁定目标和运行状态，并直接调整目标与自动锁定。关闭这个窗口后，MicLock 继续在菜单栏运行；再次打开应用会重新显示状态窗口。

角标 M 表示内建、B 蓝牙、E 外接、V 虚拟、O 其他；! 表示需要查看状态。菜单始终展示当前输入、目标和健康状态。

## 常见问题

**锁定后识别还是不好？** MicLock 保持输入设备，不改变降噪或语音识别算法。距离、环境噪声和麦克风本身仍然影响效果。

**应用仍然使用耳机麦克风？** 将应用输入改成“系统默认”；如果应用没有这个选项，手动选择电脑麦克风。MicLock 控制系统默认输入。

**目标设备断开？** 程序等待目标重新出现。可随时暂停，临时换其他输入。

**是否录音或联网？** MicLock 不录音。检查更新和提交反馈仅在你主动操作时联网，更新检查不发送系统画像。反馈发送前可查看或取消附带脱敏诊断。匿名使用统计默认关闭，开启后仅发送固定事件和随机标识，可随时关闭。

**电脑闭盖还能用内建麦克风？** 取决于机型和系统行为；闭盖时可选择可用的外接麦克风作为目标。

**如何反馈？** 在应用中点击“报告问题”，输入问题描述并提交。默认附带脱敏的系统与运行信息，可在发送前查看或取消。发送失败保留草稿，由你决定重试。无需填写系统版本或切换到飞书表单。


## 主要改进

- 使用原生 CoreAudio 事件监听，不再每两秒启动命令轮询。
- 通过稳定的设备 UID 保存目标，不受改名或系统语言影响。
- 区分“仅切换当前输入”和“设置永久锁定目标”。
- 展示正常、等待设备、持续冲突、暂停和错误等真实健康状态。
- 支持内建、蓝牙、外接、虚拟和其他设备角标。
- 中英文界面、VoiceOver 状态及增强对比度。
- 不依赖 Homebrew，不录音。默认不发送使用统计；用户可主动开启固定的匿名事件统计，随时关闭。日常配置麦克风不需要 sudo。

## 兼容性

- macOS 13 或更高版本，多个系统版本运行仍待验收。
- 同时支持 Apple Silicon 和 Intel Mac。

## 安装

1. 从[产品官网下载区](https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs#download)下载页面上标明版本与发行状态的 DMG。
2. 打开 DMG，把 `MicLock.app` 拖到 `Applications`。
3. 从“应用程序”或 Spotlight 打开 `MicLock`，按首次引导确认目标麦克风并开启自动锁定。

本地 3.2.0 当前仍是 ad-hoc 签名，未完成 Apple 公证和 Gatekeeper 正式发行验收。完成 Developer ID 签名、公证及安装验收后，才会将官网切换到正式包。打包成功不表示普通用户已经可以无障碍安装。

GitHub 的 [3.2.0 源码分支](https://github.com/liuzhengyi/miclock-macos/tree/codex/native-3.2.0) 对应当前原生版本。PR 审阅期间，主分支可能仍是较早版本。

## 从源码安装

需要当前原生版本时，在这份完整 3.2.0 源码目录运行：

~~~zsh
./scripts/fetch-sparkle.sh
./install.sh
~~~

这是高级安装方式，会额外安装 `~/.local/bin` 下的 CLI 命令；直接拖入 Applications 的用户无需使用它。当前原生源码不需要 Homebrew。安装后可以按名称或 UID 选择设备：

~~~zsh
mic-list
mic-set "BuiltInMicrophoneDevice"
~~~

## 常用命令

~~~text
mic-status                       查看当前输入和健康状态
mic-list                         列出设备、类型和稳定 UID
mic-pick                         编号选择永久锁定目标
mic-set "名称或UID"              设置并切换永久目标
mic-fix                          立即恢复一次目标设备
mic-off                          暂停自动锁定
mic-start                        开启锁定并启动程序
mic-quit                         停止锁定并退出程序
miclock switch "名称或UID"       仅切换一次并暂停自动锁定
miclock diagnostics              输出脱敏诊断信息
miclock show-menu                打开菜单栏菜单（必要时启动 MicLock）
miclock show-status              打开状态与设置（必要时启动 MicLock）
~~~

## 工作原理

MicLock 监听 CoreAudio 的默认输入和设备列表变化，仅在系统状态改变时执行纠正。
如果其他音频软件持续抢占设备，MicLock 会暂时退避并显示冲突状态，不会无限拉扯。

配置和健康状态以原子方式保存在：

~~~text
~/Library/Application Support/MicLock/
~~~

MicLock 只能控制 macOS 全局默认输入。如果 Zoom、飞书或浏览器明确选择了某个麦克风，
请在该应用中改成“系统默认”。

## 构建与验证

~~~zsh
./scripts/fetch-sparkle.sh
./tests/run.sh
python3 -m venv .layout-venv
.layout-venv/bin/pip install ds_store==1.3.2 mac_alias==2.2.3
MICLOCK_LAYOUT_PYTHON="$PWD/.layout-venv/bin/python" MICLOCK_LAYOUT_MODULES="" ./build-dmg.sh
~~~

构建结果是通过严格警告检查的通用二进制，默认使用 ad-hoc 签名。内含官方 Sparkle 2.10.0 更新框架，下载后先验证固定 SHA-256 再解包。上面的 DMG 布局依赖仅用于构建，不放入应用。可通过 `SIGNING_IDENTITY` 接入 Developer ID；Apple 公证仍是独立发行步骤。

每次推送与提交 PR 都会触发原生回归测试，验证隔离的设备、配置、纠正策略、卸载边界、反馈和统计模型，并编译两个架构、校验应用签名。测试不安装或卸载真实应用，不改变实际麦克风、不发送反馈；通过测试不等于完成 Intel 电脑、耳机、升级与安装的真实验收。网页和反馈服务的测试在对应项目中单独维护。

## 卸载

安装在 `/Applications` 或个人 `~/Applications` 的用户：在菜单或设置中选择“卸载 MicLock…”，确认后停止锁定、注销本应用的登录项，并把应用移到废纸篓。默认保留配置和反馈草稿，可主动勾选删除。只清理明确属于 MicLock 的文件，保留未知文件。开发目录与 DMG 中的应用不能从此入口卸载。

通过源码安装过 CLI 的用户，在对应源码目录执行：

~~~zsh
./uninstall.sh
~~~

卸载器拒绝 root 和符号链接越界，并且只删除能够确认属于 MicLock 的命令。

## 隐私

MicLock 不录音。检查更新和提交应用内反馈仅在用户主动操作时联网。匿名使用统计默认关闭，用户可在设置中主动开启固定事件统计，并随时关闭、清除随机标识；不含账户、硬件标识或语音输入文本。诊断信息默认隐藏设备名称和 UID，发送反馈前可以查看或取消附带诊断。

## 开源许可

MicLock 使用 [MIT License](LICENSE)。

首次安装默认关闭自动锁定。确认目标设备后，在菜单中开启，并将语音软件的麦克风设为“系统默认”。源码安装脚本升级时保留原有锁定及登录启动选择。`build/MicLock.app/Contents/MacOS/MicLock --guide` 可预览真实使用引导，不初始化状态、不启动锁定、不改变输入设备。
