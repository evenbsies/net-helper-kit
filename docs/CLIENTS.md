# 客户端配置说明

客户端输出面向**官方 Hysteria 2 客户端格式**，包括 JSON 和 URI。`./wizard.sh export` 只打印本地文件路径，不打印密码、私钥或 token；请在受控权限下读取生成文件。生成计划属于私密材料，不要上传或提交 Git。

## 官方客户端启动与 SOCKS 测试

```sh
hysteria client --config /安全路径/client.json
curl --noproxy '' --socks5-hostname 127.0.0.1:1080 https://example.com/
```

必须使用 `--socks5-hostname`，这样目标域名由远端路径解析；不要使用会在本地解析域名的 SOCKS5 形式。代理监听是本机 `127.0.0.1:1080`，不是对公网开放的服务。

## TLS 证书模式

### 自签名

- JSON 中 `tls.insecure=true`；
- JSON 和 URI 都有与服务器证书 SHA-256 匹配的 `pinSHA256`；
- 自签名证书有效期 365 天，没有自动续期。

`insecure` 不等于放弃身份校验；没有 pin 或 pin 不匹配时应拒绝连接。**两种证书模式都生成 pin**，所以换证书后都必须更新客户端 pin 和相关配置。

### 自有证书

客户端使用标准 TLS 验证。向导检查证书名覆盖服务器地址，并检查证书和无口令私钥匹配；证书链是否被客户端信任由用户保证。不要为方便打开 `insecure`。即使标准证书验证成功，也应按生成配置保留 pin。

## DNS 与过滤边界

服务端 dnsmasq 只监听 `127.0.0.1:5353`，缓存 128；上游是**明文 UDP/53**，不是 DoH 加密。规则以 dnsmasq `local=/domain/` 形式提供，匹配域名的查询类型返回 NXDOMAIN；默认只有五条小规则，并非全量广告数据库。

过滤只覆盖 Hysteria 实际收到并转发到远端 DNS 的域名请求，不保证：

- IP 直连或应用内置解析；
- 客户端本地已完成的 DNS 解析；
- DoH、DoT 或其他绕过 Hysteria 的解析路径；
- 所有应用都遵守系统代理/DNS 设置。

因此客户端需要把目标域名解析/转发交给远端配置的 DNS 路径；项目不声称提供通用全设备过滤。

## NAT 与地址

客户端 JSON/URI 使用服务器公网地址和 NAT 外部 UDP 端口；服务端内部监听端口可能不同。路由器或云平台的 UDP 转发、入站策略和回程路径由用户负责，项目不修改 NAT。确认从客户端到公网地址/外部端口的 UDP 可达后再排查客户端配置。

## 规则高级操作

规则修改会重新 `plan`，并轮换密码和证书；`apply` 会拒绝覆盖已有安装。若管理员明确选择直接维护现有安装，可先备份自己编辑的 `/etc/net-helper-kit/blocklist.conf` 并准备回滚，然后运行：

```sh
dnsmasq --test --conf-file=/etc/net-helper-kit/dnsmasq.conf
```

测试通过后再按本机 OpenRC 管理方式重启 dnsmasq。此操作不属于重装，不由项目自动执行；请自行确认备份和回滚文件。

## 兼容性

项目只承诺官方 Hysteria 客户端 JSON 和 URI 两种输出形态，不承诺任意第三方 GUI、移动端或通用客户端接受全部字段。导入前核对上游当前文档，并把认证凭据、私钥、pin 和 URI 视为秘密材料。
