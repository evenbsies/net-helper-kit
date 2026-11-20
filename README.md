# net-helper-kit

一个**低调、可审阅的本地 POSIX `sh` 向导**：把 Hysteria 2 与轻量 DNS 广告过滤组合起来，并可选使用共享子域名生成客户端配置。它不是隐身工具，不隐藏服务器 IP 或协议，也不承诺绕过网络限制。

项目面向 Alpine Linux 3.24 + OpenRC 的小型 NAT 主机；约 64 MB 只是历史设计目标，**没有性能或可用性保证**。部署前请审阅脚本、生成计划和目标环境。本项目以 MIT 许可证公开发布，仓库不包含任何真实节点配置或域名凭据。

## 先了解边界

- `plan` 交互式、全离线生成，不需要 root；默认输出新建的 `./private-output`。`apply` 只接受绝对计划目录。
- `plan` 全离线；`shared-plan` 会访问 DuckDNS：在 DuckDNS 官网手动登录并选名后，按提示用明确的公网 IPv4 更新解析，再生成普通计划。`dns-update` 只刷新已经注册的记录；`apply` 安装 apk 依赖时也需联网。
- 仅支持全新安装：目标目录、服务文件、同名用户或组只要已有一个就拒绝；不会覆盖、接管或备份旧文件。失败只清理本次新建的服务文件和目录；卸载保留 `/etc/net-helper-kit` 配置、apk 包及账号/组。
- 不修改系统 DNS、firewall、NAT 或路由器规则，不自动打洞、续期、探测 IP 或启动 DDNS 常驻进程/定时器，不接管已有 Hysteria。服务为 `nhk-dns` 与 `nhk-hysteria`，配置目录为 `/etc/net-helper-kit`。
- dnsmasq 仅监听 `127.0.0.1:5353`，缓存 128；默认规则只有 5 条小规则，不是全量广告拦截。上游是**明文 UDP/53**，不是 DoH 加密。
- OpenRC 服务依赖为 DNS 先于 Hysteria；服务使用 `after net`，不是 `need net`，因此不会接管 NAT 容器的网络生命周期。

## 一条命令搭建

先从 [GitHub 仓库](https://github.com/evenbsies/net-helper-kit) 下载完整源码并审阅。若已安装 `git`，可用 `git clone https://github.com/evenbsies/net-helper-kit.git` 获取源码；没有 `git` 时也可从仓库的 Code → Download ZIP 下载后解压。

下载并解压完整源码后，在项目目录执行（目标为 **Alpine 3.24 + OpenRC，root 用户**）：

```sh
sh ./setup.sh
```

脚本会依次检查环境和已有安装，再通过设置向导询问地址、NAT UDP 内外端口、BBR 档位、DNS 上游和证书方式；确认后安装基础依赖、生成私有计划并进入安装确认，成功后启动两个服务并执行进程检查。不需要手动把 `plan` 与 `apply` 两条命令接起来。它是**一条命令的交互式向导，不是无人值守安装**；请先审查源代码，不要 `curl | sh`，也不要只下载这一个脚本而缺少项目其他文件。

仍需准备官方 Hysteria 2 二进制及官方 SHA256 digest，并填写实际 UDP 映射；共享子域名首次官网注册/选名也仍需手动完成。脚本不自动修改防火墙或 NAT。安装基础依赖需要一次 `YES`，启动安装前还有原安装器的 `YES` 确认；取消不会回滚已安装的 apk 包、生成的私有计划或已更新的 DNS。

在普通电脑上只生成离线计划而不安装：

```sh
sh ./setup.sh --plan-only "$HOME/net-helper-plan"
```

不传路径会打开只含离线选项的菜单。此模式不会安装依赖，也不会启动共享域名联网流程。完整选项可查看 `sh ./setup.sh --help`。

## 快速开始

在项目目录中：

```sh
# 默认分步菜单
./wizard.sh

# 普通模式：完全离线，不联网、不安装
./wizard.sh plan "$HOME/net-helper-plan"

# 共享子域名模式：先按提示完成 DuckDNS 官网的人机登录/选名
./wizard.sh shared-plan "$HOME/net-helper-plan" "$HOME/net-helper-domain"

# 已有 profile 时，交互确认后按 profile 中的固定 IPv4 刷新 DNS
./wizard.sh dns-update "$HOME/net-helper-domain"

./wizard.sh apply "$HOME/net-helper-plan"     # Alpine + OpenRC 上由 root 安装
./wizard.sh status
./wizard.sh export
./wizard.sh uninstall                   # 明确输入 YES；配置保留
```

`plan` 需要 `openssl`、`sha256sum`、`awk`；共享模式还需要 `curl`、`stat`、`grep` 与标准 shell 工具。建议在有足够资源的电脑上生成计划，再把私有计划安全传到目标 Alpine。

首次申请不能由脚本代办：DuckDNS 官网的登录、验证和子域名选择必须手动完成。官方 API 只更新已注册子域名，不提供 API 一键申请。向导不会自动探测 NAT 出口 IP：请填写控制面板或网络管理员明确确认的**映射公网 IPv4**，因为 NAT 出口地址不一定是映射地址。更新前会显示 `slug.duckdns.org -> IPv4`，必须输入 `YES`。

## 共享域名如何工作

共享模式使用**共享父域名下的子域名（如 `name.duckdns.org`），并非独立拥有的二级域名**。DuckDNS 的免费 DDNS 服务由 AWS 承载并可申请共享子域名，但这不等于 SLA 或永久免费保证。解析成功不等于 UDP/NAT 可达；它不是 CDN 代理，也不隐藏服务器 IP 或 Hysteria 协议。稳定性、传播时间、服务政策和可达性均需自行验证，不能承诺稳定或免费长期可用。

向导把 token 与 profile 放在源代码树外的新目录：目录权限 `700`，`domain`、`token`、`ipv4` 文件权限 `600`；目录和文件必须是本人所有、不得是符号链接，且已存在路径拒绝覆盖。token 不进入安装计划、`/etc/net-helper-kit`、日志或公开仓库。DNS 更新与本地计划生成不是原子操作：若远程更新成功而计划生成失败，DNS 不会撤销；保留 profile。修正原因后用普通 `plan` 指定正确域名和新的输出路径重试；刷新已有解析用 `dns-update`，不要用已有 profile 再执行 `shared-plan`。

IP 变动时，先在 profile 中手动编辑 `ipv4`，保持上述权限、所有者、无符号链接和源代码树外路径，再执行 `dns-update`。没有定时器、daemon 或自动续期；`dns-update` 固定使用 profile 的明确 IPv4，不依赖自动探测。

## NAT 映射到内部低端口时

默认只允许内部端口不低于 1024。若服务商实际将 UDP 映射到内部 80 等低端口，可显式选择最小权限模式：

```sh
NHK_LOW_PORT=capability sh ./setup.sh
```

这不会把服务改成 root，也不会修改系统全局低端口策略或防火墙；安装器只给本项目的 Hysteria 程序添加 `cap_net_bind_service=ep`，以允许它由专用非 root 账号监听低端口。仅有低端口计划才需要额外的 capability 工具包。容器必须允许此 capability 和文件权限标记，否则安装会失败并清理本次项目文件；新增 apk 包与账号仍按原策略保留。不要把 SSH 的 TCP 映射当成节点 UDP 映射。

## Hysteria 2 BBR 加速档位

计划向导可选 `standard`、`conservative` 或 `aggressive`，默认 `standard`；所选档位写入服务端和客户端配置。需使用 Hysteria 2.8.0 或更新版本。这里是 Hysteria 自带的 QUIC BBR，不是 Linux TCP BBR，不需要修改内核 sysctl。`aggressive` 在某些链路可能更快，但不是保证；小内存或共享链路请先从默认档开始并小流量验证。节点 URI 不携带 BBR 档位，需使用生成的 `client.json` 才能在客户端应用所选设置。详见 [`docs/ACCELERATION.md`](docs/ACCELERATION.md)。

## 二进制、TLS、DNS 与客户端

### 上游 Hysteria 官方安装脚本（独立可选）

仓库还附带了官方安装脚本快照：[`vendor/hysteria/install_server.sh`](vendor/hysteria/install_server.sh)。从仓库 `git pull` 即可取得当前已提交版本；来源、SHA-256、许可证和更新方式见 [`vendor/hysteria/README.md`](vendor/hysteria/README.md)。

**它不属于本项目的一键安装流程，也不支持本项目目标 Alpine。** 官方脚本面向 systemd 发行版，会安装或更新系统级 Hysteria 和 systemd 服务，且只生成示例配置，仍需自行配置。仅在另一台受支持的 systemd Linux 主机上、审阅脚本后单独运行；不要在 Alpine/OpenRC 主机上运行，也不要与本项目的 OpenRC 安装混用。Alpine 上仍按下文流程准备官方二进制及官方 SHA-256 digest。

不要执行 `curl | sh`，项目不自动下载。请从 [Hysteria 官方 Releases](https://github.com/HyNetworks/hysteria/releases) 获取适合 `uname -m` 的 Linux 资产，并输入**官方 Release asset 提供的 SHA-256 digest**；脚本只重新计算本地文件进行比对。

计划含随机密码、私钥、客户端配置和 URI，**不要上传、提交 Git 或发布计划**。两种证书模式都生成 `pinSHA256`：自签名证书有效期 365 天且无自动续期，该模式必须同时使用 `insecure=true` 与固定 pin；自有证书模式检查证书名和无口令私钥匹配，使用标准验证。不要在没有 pin 的情况下关闭证书验证。DNS 过滤只覆盖 Hysteria 实际收到并转发到远端 DNS 的域名请求，不保证 IP 直连、客户端本地 DNS、DoH/DoT 或应用内置解析被过滤。

```sh
hysteria client --config /安全路径/client.json
curl --noproxy '' --socks5-hostname 127.0.0.1:1080 https://example.com/
```

使用 `--socks5-hostname`，让远端解析目标域名。更多字段、NAT 端口和 pin 说明见 [`docs/CLIENTS.md`](docs/CLIENTS.md)，共享域名细节见 [`docs/SHARED-DOMAIN.md`](docs/SHARED-DOMAIN.md)。

## 测试与许可证

本次通过 ShellCheck、shell 语法检查和 **47 项离线回归测试**，包含模拟 DuckDNS API 与真实向导整合。未访问真实 DuckDNS 账号。已在一台 Alpine 3.24.2、64 MB 限制的真实 NAT VPS 上完成低端口部署、非 root 服务检查、公网 UDP HTTPS 转发、测试域名过滤和错误指纹拒绝；未做压力、并发、长期运行或稳定性验证。BBR 档位只做离线配置验证，没有在 64 MB 主机上进行 BBR 性能或长期测试。在线 apk 曾因内存峰值失败，最终通过磁盘校验副本及官方签名离线依赖完成安装。

本项目自有代码采用 [MIT License](LICENSE)。Hysteria、dnsmasq、Alpine 包及其他依赖分别受其上游许可证约束；本项目不重新许可它们。请先阅读 [`SECURITY.md`](SECURITY.md) 与 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
