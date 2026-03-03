# OpenClaw 故障复盘记录

**日期**: 2026-03-03  
**机器**: WSL2 + Ubuntu  
**版本**: Node 22.21.0 / OpenClaw 2026.3.1

---

## 一、问题现象

1. curl 无法解析域名
2. ping 提示 Network is unreachable
3. Telegram / 飞书 agent 不回
4. Node 降级后 OpenClaw 启动报错
5. agent 提示 Channel is required

---

## 二、根因

1. WSL 未启用 systemd
2. resolv.conf 被 WSL 自动覆盖
3. systemd-resolved 未配置上游 DNS
4. Node 被错误降级（OpenClaw 依赖 Node 22 API）
5. 双通道情况下未指定 --channel

---

## 三、最终稳定结构

### 系统层
- systemd=true
- systemd-resolved 管理 DNS
- resolv.conf 指向 stub-resolv.conf
- DNS Servers: 1.1.1.1 / 8.8.8.8 / 9.9.9.9
- IPv4 优先

### 运行层
- Node v22.x
- OpenClaw 2026.3.1

### 应用层
- Telegram OK
- Feishu OK
- agent 使用 --deliver 时必须带 --channel

---

## 四、最终验证命令

### 网络
```bash
ip route
ping -c 2 1.1.1.1
```

### DNS
```bash
resolvectl status
getent hosts api.telegram.org
```

### 版本
```bash
node -v
openclaw --version
```

### 通道
```bash
openclaw health
```

### agent 测试
```bash
openclaw agent --to telegram:direct:1195971164 --message "test" --deliver --channel telegram
```

---

## 五、永久规则（必须遵守）

1. **不手写 resolv.conf**
2. **不锁 resolv.conf**
3. **不降级 Node**
4. **多通道必须写 --channel**

---

## 六、当前状态

- [x] 网络正常
- [x] DNS 正常
- [x] Node 正确
- [x] OpenClaw 正常
- [x] 双通道可收发
- [x] agent 正常

---

*记录时间: 2026-03-03 14:28*  
*记录者: HoneyRay*  
*状态: 已解决，已稳定*
