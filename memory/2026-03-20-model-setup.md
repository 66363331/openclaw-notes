# MiniMax 模型配置总结 - 2026-03-20

## ✅ 已测试成功的模型

### 1. 图片生成 (image-01)
- **状态**: ✅ 测试成功
- **脚本**: `~/.openclaw/workspace/scripts/minimax-image-gen.sh`
- **使用方法**: 
  ```bash
  ./minimax-image-gen.sh "描述" [比例]
  # 比例: 1:1, 16:9, 4:3, 3:2, 2:3, 3:4
  ```
- **API**: `POST https://api.minimaxi.com/v1/image_generation`

### 2. 图片分析 (Vision)
- **状态**: ✅ 已配置（通过 M2.7）
- **使用方法**: 直接发图片给我，我就能分析

## 📝 已写好脚本的模型

### 3. 语音合成 (Speech)
- **脚本**: `~/.openclaw/workspace/scripts/minimax-speech.sh`
- **使用方法**:
  ```bash
  ./minimax-speech.sh "文本" [voice_id] [model]
  # model: speech-2.8-hd (默认), speech-2.8-turbo
  # voice_id: female-tianmei (默认), male-qn-qingse 等
  ```
- **API**: `POST https://api.minimaxi.com/v1/t2a_v2`

### 4. 音乐生成 (Music)
- **脚本**: `~/.openclaw/workspace/scripts/minimax-music.sh`
- **使用方法**:
  ```bash
  ./minimax-music.sh "音乐描述" [歌词]
  # model: music-2.5+
  ```
- **API**: `POST https://api.minimaxi.com/v1/music_generation`

### 5. 视频生成 (Video)
- **脚本**: `~/.openclaw/workspace/scripts/minimax-video.sh`
- **使用方法**:
  ```bash
  ./minimax-video.sh "视频描述" [model]
  # model: MiniMax-Hailuo-2.3-Fast (默认), MiniMax-Hailuo-2.3, MiniMax-Hailuo-02, T2V-01
  ```
- **API**: `POST https://api.minimaxi.com/v1/video_generation`

## 📌 重要说明
- 所有脚本都需要设置环境变量 `MINIMAX_API_KEY`
- API Key 格式: `sk-cp-1ExOgDOg...` (Token Plan Key)
- 脚本位置: `~/.openclaw/workspace/scripts/`

## 🔧 待完成任务
- [ ] 测试语音合成脚本
- [ ] 测试音乐生成脚本
- [ ] 测试视频生成脚本
- [ ] 配置 OpenClaw Skill 集成这些功能
