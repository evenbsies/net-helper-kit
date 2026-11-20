# Hysteria 2 BBR 拥塞控制

本项目把 Hysteria 2 自带的 QUIC 拥塞控制作为可选调校项。生成计划时可选 `standard`、`conservative` 或 `aggressive`，默认是 `standard`。所选档位同时写入服务端 `server.yaml` 和客户端 `client.json`。要使配置生效，服务端和客户端都需使用 Hysteria 2.8.0 或更新版本；安装器会检查服务端版本，旧版本不支持这些可配置的 BBR profile。

```yaml
congestion:
  type: bbr
  bbrProfile: aggressive
```

这里的 BBR 是 Hysteria 为 QUIC 实现的拥塞控制，不是 Linux TCP 的 BBR；无需也不应为了 Hysteria 去改 `net.ipv4.tcp_congestion_control` 等全局内核参数。官方说明列出 `standard`（默认）、`conservative` 和 `aggressive`，并提醒这些算法细节可能随 Hysteria 版本变化：[服务器配置](https://v2.hysteria.network/docs/advanced/Full-Server-Config/) · [客户端配置](https://v2.hysteria.network/docs/advanced/Full-Client-Config/) · [2.8.0 更新记录](https://v2.hysteria.network/docs/Changelog/)。

## 如何启用

在交互式 `plan` 或 `shared-plan` 中，BBR 档位提示可直接输入 `aggressive`。完成计划后，使用生成的 `client.json` 配合官方客户端配置运行；本项目生成的 Hysteria URI 只包含连接所需的认证、TLS 与 pin 信息，不包含拥塞控制档位，因此导入 URI 的客户端可能继续使用自己的默认 profile。

`congestion` 是本地端点设置，不在协议中协商。服务端和客户端都写入所选档位，便于两个发送方向使用一致设置，但两端并不要求完全匹配。当前生成配置不设置 bandwidth，因此使用 BBR；如果另行给客户端配置带宽，Hysteria 会按官方规则对相应方向选择 Brutal，而不是 BBR。参见官方[带宽与拥塞控制说明](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)。

## 小主机注意事项

- `aggressive` 在特定链路上可能获得更高吞吐，但并非总是更快，也没有固定速度保证；繁忙、带宽很窄或与他人共享的链路上，它可能增加对其他流量的竞争并恶化时延或稳定性。先用低流量验证，再考虑保留此档位。
- 对 64 MB 一类的小容器，建议从默认的 `standard` 开始；只有在对比测试确认效果并可接受时再改成 `aggressive`。也可试 `conservative`。当前项目没有在 64 MB 下对 BBR 档位做压力、并发或长期稳定性测试。
- 项目的 `GOMEMLIMIT=24MiB` 是 Go 运行时提示，不是进程 RSS 或容器硬上限。改变 BBR 档位不能解决内存不足，也不代表服务不会被 OOM 杀掉。
- BBR 决定发送端如何响应网络拥塞，不会改变 NAT 端口映射、服务端 DNS 过滤范围或客户端绕过代理的行为。

## URI 与客户端兼容性

Hysteria 官方 [URI Scheme](https://v2.hysteria.network/docs/developers/URI-Scheme/) 列出的标准参数不包含 BBR profile。需要应用所选档位时，使用 `client.json` 或在兼容客户端中手工设置对应的 `congestion` 字段；第三方客户端是否支持该字段须以其自身文档为准。不要因为导入 URI 成功就假定客户端也启用了 `aggressive`。
