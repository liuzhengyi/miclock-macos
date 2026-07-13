# MicLock：macOS 全局麦克风锁定

<p align="center">
  <img src="docs/MicLock-icon.png" width="160" alt="MicLock 图标">
</p>

[English](README.md)

MicLock 让 AirPods 继续负责声音输出，同时把 macOS 的全局默认输入持续保持在
MacBook 内建麦克风。它不会录音，也不会修改输出设备。

## 主要功能

- 原生 macOS 菜单栏应用，不占用 Dock。
- AirPods 重连并抢走输入后，通常在两秒内切回目标麦克风。
- 菜单栏通过蓝色 M、青色 A、橙色 O 和红色 ! 显示设备类型。
- 麦克风主体自动适配菜单栏的白色或深色样式。
- 提供查看、切换、暂停、恢复和退出的命令行快捷方式。
- 只运行当前用户的 LaunchAgent，不需要 <code>sudo</code>。
- 不联网、无遥测、不采集音频。

## 兼容性

- macOS Tahoe 26 或更高版本。
- Apple Silicon。
- 源码安装依赖 Homebrew 的 <code>switchaudio-osx</code> 1.2.2。

## 通过 DMG 安装

1. 从 [GitHub Releases](https://github.com/liuzhengyi/miclock-macos/releases/latest)
   下载最新 DMG。
2. 打开 DMG，运行“安装 MicLock.command”。
3. 安装完成后，MicLock 会显示在菜单栏；也可以用 Spotlight 搜索
   <code>MicLock</code> 启动。

当前社区构建使用 ad-hoc 签名，尚未经过 Apple 公证。如果首次启动被
Gatekeeper 阻止，请按住 Control 点击 <code>MicLock.app</code>，选择“打开”
并确认。

## 从源码安装

~~~zsh
git clone https://github.com/liuzhengyi/miclock-macos.git
cd miclock-macos
chmod +x *.sh miclock
./install.sh
./install-menu-app.sh
~~~

明确指定目标设备：

~~~zsh
SwitchAudioSource -a -t input
./install.sh --device "MacBook Air 麦克风"
~~~

## 常用命令

~~~zsh
mic-status                         # 查看状态
mic-list                           # 列出输入设备
mic-pick                           # 编号选择目标设备
mic-set "设备名称"                 # 指定并锁定设备
mic-fix                            # 立即纠正一次
mic-off                            # 暂停自动锁定
mic-on                             # 恢复自动锁定
mic-quit                           # 停止锁定，恢复系统行为
mic-start                          # 再次启动
miclock logs                       # 查看日志
~~~

如果终端找不到这些命令：

~~~zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
~~~

## 工作原理

<code>com.user.mic-input-lock</code> LaunchAgent 每两秒读取一次 CoreAudio
默认输入，发现设备与配置不一致时自动切回。
<code>com.user.mic-input-lock-menu</code> 负责菜单栏界面。

该方案锁定的是 macOS 全局默认输入。如果 Zoom、飞书或浏览器在自己的设置中
明确指定了其他麦克风，请把该应用改为“系统默认”。

## 构建安装包

~~~zsh
brew install switchaudio-osx
./build-dmg.sh
~~~

公开正式分发前，建议使用 Developer ID、Hardened Runtime 和 Apple 公证替代
当前的 ad-hoc 签名。

## 卸载

DMG 用户运行“卸载 MicLock.command”。源码用户执行：

~~~zsh
./uninstall-menu-app.sh
./uninstall.sh --purge-logs
~~~

## 开源许可

MicLock 使用 [MIT License](LICENSE)。发行包内嵌的
<code>SwitchAudioSource</code> 是独立的 MIT 开源项目，并随应用附带其许可
证文本。
