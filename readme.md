# 🍡 Godot AI Desktop Pet (多模态毒舌 AI 桌宠)

![Godot Engine](https://img.shields.io/badge/Godot-4.3-blue?logo=godotengine&logoColor=white)
![LLM Integration](https://img.shields.io/badge/AI-Vision%20%7C%20ASR%20%7C%20TTS-orange)
![License](https://img.shields.io/badge/License-MIT-green)

A lightweight, fully native multi-modal AI desktop pet framework built with Godot 4. It watches your screen, listens to your voice, remembers your gaming fails, and roasts you in real-time. 

这是一个基于 Godot 4 引擎原生开发的多模态 AI 桌宠底层框架。它能看懂你的屏幕、听懂你的语音、记住你的下饭操作，并以极低的性能损耗在桌面上实时吐槽你。

---

## 🧠 内置模型矩阵 (Model Architecture)

本项目目前深度绑定了以下两家云端 AI 服务，实现了极速的“听、说、看、想”：

* **👁️ 视觉慢脑 (Vision Brain):** 火山引擎 豆包 `Doubao-Seed-1.6-vision` (用于精准分析屏幕画面与游戏生死状态)
* **⚡ 语音快脑 (Fast Brain):** 火山引擎 豆包 `Doubao-1.5-lite-32k` (用于毫秒级的日常对话与情绪反馈)
* **👂 极速听觉 (ASR):** 硅基流动 `FunAudioLLM/SenseVoiceSmall` (用于高精度的麦克风语音转文字)
* **👄 傲娇声带 (TTS):** 硅基流动 `FunAudioLLM/CosyVoice2-0.5B:diana` (自带生动语气的拟真语音合成)

## 🚀 快速开始 (Getting Started)

### 选项 A：直接运行成品 (玩家推荐)
请在右侧的 **Releases** 标签页下载最新打包的 `.zip` 文件，解压后按照以下步骤启动：

1. **双击启动:** 运行 `desktop lab29.exe`，你会看到一颗黄色的果冻小球从屏幕上方掉落到桌面中间。
2. **呼出控制台:** 在电脑右下角的任务栏托盘中，找到小球的图标。**右键点击图标 -> 选择“⚙️ 显示控制台”**，即可呼出 UI 设置面板。
3. **注入灵魂 (配置密钥):** 在控制台的输入框内，**严格使用竖线 `|` 分隔**，填入你的四段 API 信息：
   ```text
   豆包API密钥|视觉模型EP接入点|极速文本模型EP接入点|硅基流动API密钥
(例如：sk-xxx|ep-2026...|ep-2026...|sk-silicon...)
4. 开始互动: 按住鼠标可以拖拽小球；直接对着麦克风说话即可触发互动。

选项 B：源码运行 (开发者推荐)
下载本仓库源码，使用 Godot 4.x 打开 project.godot。

点击右上角“运行项目”即可进入调试模式。

✨ 核心特性 (Key Features)
双脑异步架构: 慢脑截屏看戏，快脑听音秒回，互不干扰。

梦境记忆压缩: 引入长短期记忆池 (Rolling Memory)。短期流水账存满后，AI 会“做梦”总结为长期档案并写入本地硬盘。

智能语音打断: 实时麦克风音量检测 (VAD)，玩家一开口，桌宠立刻闭嘴。

OBS 直播字幕联动: 彻底解决 Windows 透明窗口渲染撕裂问题，将字幕静默输出为本地 txt，供 OBS 零损耗读取展示。

🤝 贡献与参与 (Contributing)
欢迎提交 Pull Request 或 Issue！特别欢迎以下方向的大佬加入：

Live2D / VRM 虚拟皮套原生接入 (优先级极高！)

更多的桌面交互小玩具（如下落方块、鼠标跟随等）

📄 开源协议 (License)
本项目采用 MIT 协议开源。你可以自由修改、分发甚至用于商业项目。如果你用这个框架做出了百万粉的 VTuber，记得回来给个 Star！⭐
