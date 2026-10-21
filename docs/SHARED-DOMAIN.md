# 共享子域名流程

本页说明 `net-helper-kit` 的 DuckDNS 共享子域名功能。它把 Hysteria 2、DNS 广告过滤和一个可手动维护的域名入口合并到同一向导中，但**不提供隐身、隐藏流量或网络绕过**。

## 先说清楚它是什么

这里使用的是**共享父域名下的子域名（如 `name.duckdns.org`），并非独立拥有的二级域名**。DuckDNS 官方页面说明其[免费 DDNS 服务由 AWS 承载](https://www.duckdns.org/why.jsp)并可申请共享子域名；这不构成 SLA，也不保证永久免费或长期稳定。它不是 CDN 代理，不隐藏服务器 IP 或 Hysteria 协议。DNS 解析成功也不代表 UDP/NAT 可达、端口已转发或客户端能连通。

首次官网登录、验证和选择 slug 必须由用户在 [DuckDNS 官网](https://www.duckdns.org) 手动完成。不能说 API 一键全自动申请：官方 [API](https://www.duckdns.org/spec.jsp) 的 `update` 接口只更新已注册子域名，返回 `OK` 或 `KO`。

## 首次生成计划

```sh
./wizard.sh shared-plan "$HOME/net-helper-plan" "$HOME/net-helper-domain"
```

按顺序完成：

1. 在官网手动登录并选择一个 slug；向导不会代办人机验证或申请。
2. 输入已选 slug、控制面板/网络管理员明确确认的公网 IPv4 和 DuckDNS token（终端输入不回显）。
3. 输入 `YES` 确认目标，例如 `name.duckdns.org -> 你的实际公网IPv4`（文档测试网段不可用于部署），然后向导通过 HTTPS 调用官方 update API。
4. API 成功后把 profile 写入第二个参数指定的凭据目录，并调用普通 `plan`，生成使用 `name.duckdns.org` 的客户端配置。
5. 之后仍需审阅计划，另行执行 `apply`；共享流程不会安装系统。

IPv4 **不会自动探测**。请填写实际映射到此服务的明确公网 IPv4；NAT 出口 IP 不一定是端口映射 IP。私有、回环、链路本地、组播和保留地址会被拒绝。

## profile 的位置和权限

凭据目录必须是源代码树外的绝对路径，并且开始时不存在；向导拒绝覆盖已有目录。完成后应保持：

```text
/安全/域名凭据目录/       # 目录：本人所有，700，非符号链接
├── domain                # 普通文件：本人所有，600，内容为 slug
├── token                 # 普通文件：本人所有，600，DuckDNS token
└── ipv4                  # 普通文件：本人所有，600，固定公网 IPv4
```

token 不进入安装计划、`/etc/net-helper-kit`、日志、shell 历史或公开仓库。不要把 profile 复制进项目目录。若权限、所有者、路径或符号链接不符合要求，`dns-update` 会拒绝执行。

## 刷新已有解析

```sh
./wizard.sh dns-update "$HOME/net-helper-domain"
```

命令会读取 `domain`、`token`、`ipv4`，显示目标并要求交互输入 `YES`，再通过 HTTPS 更新。它只使用 profile 中保存的固定 IPv4，不自动探测，也不启动定时任务、daemon 或自动续期。成功信息只表示 DuckDNS 接受更新，不表示传播完成或 UDP 服务可达。

IP 变化时：

1. 在 profile 外部安全编辑 `ipv4`；不要替换成符号链接。
2. 保持目录 `700`、三个文件 `600`，且均由本人所有。
3. 再次运行 `dns-update` 并确认目标。

## 失败与重试

DNS 远程更新和本地计划生成无法原子提交。可能出现“DNS 已更新，但计划生成失败”；向导不会撤销 DNS，并会保留 profile。此时可检查计划路径和普通配置输入，执行普通 `plan`（必须使用新的输出目录），并输入已绑定的正确域名。已有 profile 只通过 `dns-update` 刷新；`shared-plan` 不接受已有 profile，不能用原参数直接重试。不要把此状态描述为回滚成功。

若请求超时或响应异常，远程更新是否完成可能不确定；先在官网检查，不能把报错当作远程未修改的证明。账号 token 可能管理同一账号下的多个子域名，泄露时需在官网更换。

通过你常用的 DNS 工具检查 A 记录是否为预期地址，并检查是否残留错误的 AAAA 记录；本项目仅更新 IPv4，不会自动清空已有 IPv6 记录。

传播、UDP 端口转发、云防火墙、路由器 NAT、证书 pin 和客户端配置需分别排查。共享域名只提供 DNS 记录更新，不改变项目不接管 firewall/NAT、不保证客户端可达的边界。

## 安全检查清单

- [ ] 官网首次登录、验证和选名由本人手动完成。
- [ ] profile 在源代码树外、路径不存在时新建，且不可覆盖。
- [ ] 目录 `700`，`domain`、`token`、`ipv4` 均为无符号链接的 `600` 文件并由本人所有。
- [ ] IPv4 是明确的映射公网地址，而非盲目采用 NAT 出口探测结果。
- [ ] token 未进入计划、`/etc/net-helper-kit`、日志或公开 repo。
- [ ] 已理解 DNS 更新成功不等于解析传播、UDP/NAT 可达、CDN 代理、隐身或永久免费。
