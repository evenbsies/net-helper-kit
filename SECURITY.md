# 安全政策

## 范围

net-helper-kit 是本地可审阅的 POSIX `sh` 向导，用于生成/安装 Hysteria 2 与 dnsmasq 配置，并可手动维护 DuckDNS 共享子域名解析。它不修改系统 DNS、firewall、NAT 或路由，不接管已有 Hysteria，不宣称隐身或隐藏流量。安全结论应以实际脚本、目标 Alpine 环境、DuckDNS 官方文档和 Hysteria 上游文档为准。

## 安装安全边界

`setup.sh` 是现有 `plan`/`shared-plan` 与 `apply` 的交互式串联入口，不绕过确认、完整性校验或全新安装限制。默认模式只允许 Alpine 3.24 + OpenRC 的 root 环境，并在系统变更前检查旧安装；安装基础依赖需单独同意，且这些 apk 包不随取消后续步骤回滚。`--plan-only` 不安装依赖、不联网，且不提供共享域名联网选项。完整源码包应先审阅，不支持把远程脚本管道直接交给 root shell。

- `plan` 仍是全离线流程；不联网、不安装、不自动下载。`apply` 只在 Alpine/OpenRC 上以 root 执行，且仅允许全新目标。
- 任何目标目录、服务文件、同名用户或组已存在都拒绝；不覆盖、不接管、不备份旧文件。服务名为 `nhk-dns`、`nhk-hysteria`，配置目录为 `/etc/net-helper-kit`。
- 失败只清理本次新建的服务和目录；apk 包及账号/组保留。卸载移除本项目服务和程序，但保留配置、apk 包及账号/组。重试/重装须由管理员审查，手动备份并移走保留配置，逐项确认并删除未使用的本项目账号/组；不要复制危险的泛用删除命令。
- 二进制必须由管理员从 [官方 Releases](https://github.com/HyNetworks/hysteria/releases) 获取并核验官方 asset digest。项目不使用 `curl | sh`。

## 共享域名与 token

共享域名是**共享父域名下的子域名（如 `name.duckdns.org`），并非独立拥有的二级域名**。DuckDNS 官方 API 只能更新已注册子域名；首次官网登录、验证和选名是不可省略的人机操作，不能描述为 API 一键全自动申请。免费 DDNS/共享子域名不等于 SLA 或永久免费保证；它不是 CDN 代理，也不隐藏服务器 IP 或协议。DNS 解析成功不等于 UDP/NAT 可达。

`shared-plan` 只接受源代码树外、尚不存在且不可覆盖的 profile 目录。向导要求手动输入 slug、token 和明确的可路由公网 IPv4，显示目标后要求输入 `YES`，通过 HTTPS 更新 DuckDNS，再保存 profile 并调用普通 `plan` 生成带域名的客户端配置。它不会自动探测 IP；NAT 出口 IP 不一定是实际映射 IP。

profile 必须由本人所有、无符号链接、目录 `700`，其中 `domain`、`token`、`ipv4` 必须为本人所有的普通文件且权限 `600`。真实 token 不进入安装计划、`/etc/net-helper-kit`、日志、测试夹具或公开 repo；测试仅使用虚构 UUID。DuckDNS token 可能控制同一账号下的多个子域名，泄露后应到官网更换。profile 不允许覆盖，且必须留在源代码树外。DNS 远程更新与本地计划生成无法原子提交：更新成功而计划失败时不会撤销 DNS；保留 profile 供重试或普通 `plan` 使用，并确认 host 正确。

IP 变化没有自动续期、定时器或 daemon。请先手动编辑 profile 的 `ipv4`，保持 `700/600`、所有者和无符号链接要求，再执行：

```sh
./wizard.sh dns-update "$HOME/net-helper-domain"
```

该命令交互确认后只使用 profile 中的固定 IPv4，不依赖自动探测。取消或更新失败不会修改 profile。请求超时不能证明远程记录未改变；先在官网核对再重试。

## 计划、秘密与 TLS

计划含密码、私钥、客户端 JSON 和 URI，不应上传、提交 Git、截图或发布。文档和测试只使用占位符；不要记录真实地址、端口、密码、私钥、token 或公网主机信息。自签名证书有效期 365 天且没有自动续期；两种证书模式均生成 pin，换证书后必须更新客户端 pin。自有证书模式不要打开 `insecure`。

## 服务与 DNS

dnsmasq 仅绑定 `127.0.0.1:5353`，上游是明文 UDP/53，不是 DoH。OpenRC 使用 `after net` 而不是 `need net`，DNS 服务先于 Hysteria，不接管 NAT 容器网络。过滤只覆盖 Hysteria 收到并转发的域名请求，不保证 IP 直连、客户端本地解析、DoH/DoT 或应用内置解析受到过滤。

## 报告漏洞

请优先通过私下渠道向维护者报告，提供受影响版本/提交、Alpine/OpenRC 版本、最小复现步骤、预期与实际行为、脱敏日志及修复建议。不要附密码、私钥、真实地址、token 或生产配置；使用占位符。若暂无私下渠道，请提交不含秘密的 issue，并在标题注明 `security`，不要发布可直接利用的完整秘密或生产目标。

本项目不保证在所有第三方客户端、NAT、内存配置或 DNS 绕过场景提供完整安全边界；Hysteria、dnsmasq、Alpine、OpenRC 与 DuckDNS 的上游公告和政策仍需单独关注。
