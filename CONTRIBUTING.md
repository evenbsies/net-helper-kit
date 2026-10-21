# 贡献指南

感谢审查和贡献 net-helper-kit。项目优先保证**可读、可审计、少依赖和保守的安装边界**，而不是隐藏复杂的自动化。本项目以 MIT 许可证公开发布；请勿提交任何真实节点配置、私有计划或域名凭据。

## 开始前

1. 阅读 [`README.md`](README.md)、[`SECURITY.md`](SECURITY.md)、[`docs/SHARED-DOMAIN.md`](docs/SHARED-DOMAIN.md) 和本文件。
2. 对照 [Hysteria 服务端配置](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)、[客户端配置](https://v2.hysteria.network/docs/advanced/Full-Client-Config/)、[dnsmasq 手册](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) 与 [DuckDNS update API](https://www.duckdns.org/spec.jsp) 核对字段。
3. 只在隔离的本地环境或明确控制的测试主机试验；不要把真实凭据、profile、计划或生产配置写入仓库。

## 代码和配置原则

- 保持 POSIX `sh`，不要无必要引入 Bash 语法或额外依赖；普通 `plan` 必须保持全离线。
- `shared-plan` 必须保留官网首次登录/选名的人机步骤，不能声称 API 自动申请。网络更新仅通过 HTTPS 调用 DuckDNS 官方 API，且只更新已注册子域名。
- 共享域名必须明确写作共享父域名下的子域名（如 `name.duckdns.org`），不是独立二级域名；不得宣传隐身、隐藏流量、CDN 代理、SLA、永久免费或稳定可达。
- 不自动探测 IP。要求用户明确提供映射公网 IPv4，并拒绝私有、回环、链路本地、组播和保留地址。`dns-update` 固定使用 profile 的 `ipv4`。
- profile 必须在源代码树外、不可覆盖、无符号链接且由本人所有；目录 `700`，`domain`/`token`/`ipv4` 文件 `600`。token 不得进入计划、安装系统、日志、测试夹具或公开 repo。不得添加定时器、daemon 或自动续期。
- DNS 更新和普通 `plan` 不是原子事务；更新成功后计划失败时必须保留可重试 profile，不得虚假声称已回滚远程 DNS。
- 安装仅允许全新目标；已有目录、服务文件、同名用户或组一律拒绝。维持 `nhk-dns`、`nhk-hysteria`、`/etc/net-helper-kit` 约定。
- 维持 dnsmasq `127.0.0.1:5353`、明文 UDP/53 上游、缓存 128、DNS 先启动；OpenRC 使用 `after net` 而非 `need net`，不接管 NAT 容器网络。
- 维持 TLS pin、自签证书 365 天且不自动续期、可审阅的小规则集和失败清理边界。

## 本地检查

```sh
./tests/run.sh
```

当前版本已通过 ShellCheck、shell 语法检查和 41 项离线回归测试；后续改动仍须重新执行，不要新增或宣称未经执行的测试数字。不要宣称本次已实测新版 Alpine 完整生命周期、真实 VPS、64 MB 限制、长期运行、NAT/UDP 可达性或永久免费服务。真实网络检查必须明确标注并使用占位符凭据；不要把 DuckDNS 更新写入常规离线测试。

修改安装、卸载、权限、profile、TLS pin、URI 或服务依赖时，应补充可重复的离线测试，并说明未覆盖的 Alpine/OpenRC/NAT 情况。避免触碰真实 `/etc`；需要 root 或真实网络的检查应优先使用临时根目录或网络命名空间。

## 提交与审查

提交说明简洁写明动机、行为变化、测试命令和已知限制。审查重点包括 shell quoting、路径穿越、权限、符号链接、凭据泄露、明确 IPv4、HTTPS、DuckDNS 返回值、远程更新与本地计划的非原子性、官方 digest 信任、全新安装拒绝覆盖、失败清理范围、账号保留、服务顺序、明文 DNS 上游和 pin 行为。

贡献本项目自有代码即表示你有权按 [MIT License](LICENSE) 提交；第三方代码和依赖保留其上游许可证。
