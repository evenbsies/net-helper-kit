#!/bin/sh
# SPDX-License-Identifier: MIT
plan() {
    need openssl; need sha256sum; need awk
    OUT=$1
    valid_path "$OUT" || die '输出目录必须是绝对路径，仅含字母、数字、_ . / -，且不能含 ..'
    [ ! -e "$OUT" ] && [ ! -L "$OUT" ] || die '输出目录已存在；为避免覆盖密钥请使用新目录'
    [ -d "$(dirname "$OUT")" ] || die '输出目录的父目录不存在'
    printf '%s\n' '仅生成本地计划，不联网、不安装、不修改现有服务。' 'IPv4/域名受支持；IPv6 端点暂不支持。内外端口必须按 NAT 面板实际映射填写。'
    if [ -n "${NHK_HOST_DEFAULT:-}" ]; then
        HOST=$NHK_HOST_DEFAULT
        printf '使用共享域名: %s\n' "$HOST"
    else
        ask_value '服务器公网 IPv4 或域名（不自动探测）' 'node.example.com'; HOST=$ANSWER
    fi
    valid_host "$HOST" || die '服务器地址无效'
    ask_value '容器内部 UDP 监听端口' '24443'; INTERNAL=$ANSWER
    valid_port "$INTERNAL" || die '内部端口必须为 1–65535（不带前导零）'
    [ "$INTERNAL" -ge 1024 ] || die '独立非特权服务仅支持内部端口 >=1024'
    [ "$INTERNAL" -ne 5353 ] || die '5353 已保留给本地 DNS'
    ask_value 'NAT 公网 UDP 端口（客户端使用）' "$INTERNAL"; EXTERNAL=$ANSWER
    valid_port "$EXTERNAL" || die '外部端口无效'
    ask_value '上游 DNS IPv4（明文 UDP/53）' '1.1.1.1'; UPSTREAM=$ANSWER
    valid_ipv4 "$UPSTREAM" || die '上游仅支持 IPv4'
    case "$UPSTREAM" in 127.*|0.*|255.*) die '禁止回环、未指定或广播上游，避免 DNS 循环' ;; esac
    ask_value '已从官方取得的 Hysteria 2 Linux 二进制绝对路径' ''; BINARY=$ANSWER
    valid_path "$BINARY" && [ -f "$BINARY" ] && [ ! -L "$BINARY" ] || die '需要普通二进制文件的绝对路径'
    ask_value '可信来源 SHA256（不是脚本自己下载后声称可信的校验值）' ''; EXPECTED=$(printf '%s' "$ANSWER" | tr 'A-F' 'a-f')
    valid_sha "$EXPECTED" || die 'SHA256 必须为 64 位十六进制'
    [ "$(sha_file "$BINARY")" = "$EXPECTED" ] || die '二进制 SHA256 不匹配'
    ask_value '证书模式: pin=生成自签并固定指纹；cert=使用已有受信任证书' 'pin'; MODE=$ANSWER
    case "$MODE" in
        pin) ;;
        cert)
            ask_value '证书链 PEM 绝对路径' ''; CERT=$ANSWER
            ask_value '私钥 PEM 绝对路径（无口令，供服务启动）' ''; KEY=$ANSWER
            valid_path "$CERT" && valid_path "$KEY" || die '证书路径无效'
            [ -f "$CERT" ] && [ -f "$KEY" ] && [ ! -L "$CERT" ] && [ ! -L "$KEY" ] || die '证书或私钥不存在/不是普通文件'
            openssl x509 -in "$CERT" -noout -checkend 604800 >/dev/null || die '证书已过期或将在 7 天内过期'
            if valid_ipv4 "$HOST"; then
                openssl x509 -in "$CERT" -noout -checkip "$HOST" | grep -F 'does match certificate' >/dev/null || die '证书不匹配服务器 IP'
            else
                openssl x509 -in "$CERT" -noout -checkhost "$HOST" | grep -F 'does match certificate' >/dev/null || die '证书不匹配服务器域名'
            fi
            PUB_CERT=$(openssl x509 -in "$CERT" -pubkey -noout | sha256sum)
            PUB_KEY=$(openssl pkey -in "$KEY" -passin pass: -pubout 2>/dev/null | sha256sum)
            [ "$PUB_CERT" = "$PUB_KEY" ] || die '证书与无口令私钥不匹配'
            ;;
        *) die '证书模式只能是 pin 或 cert' ;;
    esac
    STAGE=$(mktemp -d "$(dirname "$OUT")/.nhk-plan.XXXXXX")
    trap 'rm -rf -- "$STAGE"' EXIT
    trap 'exit 1' HUP INT TERM
    if [ "$MODE" = pin ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
            -days 365 -subj "/CN=$HOST" -keyout "$STAGE/server.key" -out "$STAGE/server.crt" >/dev/null 2>&1
        INSECURE=true; INSECURE_URI=1
    else
        cp "$CERT" "$STAGE/server.crt"; cp "$KEY" "$STAGE/server.key"
        INSECURE=false; INSECURE_URI=0
    fi
    PIN=$(openssl x509 -in "$STAGE/server.crt" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
    valid_sha "$PIN" || die '证书指纹生成失败'
    PASSWORD=$(openssl rand -hex 32)
    cp "$BINARY" "$STAGE/hysteria"
    printf '%s\n' "$EXPECTED" > "$STAGE/binary.sha256"
    printf '%s\n' "$MODE" > "$STAGE/tls-mode"
    printf '1\n' > "$STAGE/format-version"
    # Rule compiler accepts only domain names; no downloaded shell/config directives.
    awk -f "$BASE/lib/rules.awk" "$BASE/rules/blocklist.txt" > "$STAGE/blocklist.conf" || die '规则列表无效'
    cat > "$STAGE/dnsmasq.conf" <<EOF
# Private loopback-only instance; system resolv.conf is not changed.
listen-address=127.0.0.1
bind-interfaces
port=5353
no-resolv
no-hosts
server=$UPSTREAM
cache-size=128
dns-forward-max=32
neg-ttl=60
user=nhk-dns
group=nhk-dns
conf-file=/etc/net-helper-kit/blocklist.conf
EOF
    cat > "$STAGE/server.yaml" <<EOF
listen: 0.0.0.0:$INTERNAL
tls:
  cert: /etc/net-helper-kit/server.crt
  key: /etc/net-helper-kit/server.key
auth:
  type: password
  password: "$PASSWORD"
resolver:
  type: udp
  udp:
    addr: 127.0.0.1:5353
    timeout: 4s
quic:
  initStreamReceiveWindow: 2097152
  maxStreamReceiveWindow: 2097152
  initConnReceiveWindow: 5242880
  maxConnReceiveWindow: 5242880
  maxIncomingStreams: 32
  maxIdleTimeout: 30s
udpIdleTimeout: 30s
speedTest: false
EOF
    cat > "$STAGE/client.json" <<EOF
{
  "server": "$HOST:$EXTERNAL",
  "auth": "$PASSWORD",
  "tls": {
    "sni": "$HOST",
    "insecure": $INSECURE,
    "pinSHA256": "$PIN"
  },
  "socks5": {"listen": "127.0.0.1:1080"}
}
EOF
    printf 'hysteria2://%s@%s:%s/?sni=%s&insecure=%s&pinSHA256=%s#net-helper\n' \
        "$PASSWORD" "$HOST" "$EXTERNAL" "$HOST" "$INSECURE_URI" "$PIN" > "$STAGE/node-uri.txt"
    chmod 600 "$STAGE"/*; chmod 700 "$STAGE/hysteria"
    (cd "$STAGE" && for item in $PLAN_FILES; do sha256sum "$item"; done) > "$STAGE/SHA256SUMS"
    mv "$STAGE" "$OUT"
    trap - EXIT HUP INT TERM
    printf '\n已生成私有计划: %s\n' "$OUT"
    printf '%s\n' '包含随机节点密码和私钥，不要上传、截图或提交 Git。' \
        '自签模式必须同时启用固定 pinSHA256；第三方客户端不支持固定指纹时不要导入。' \
        '请审阅配置、证书、二进制来源和 NAT UDP 映射，再在目标 Alpine 上执行 apply。' \
        '当前没有修改目标 VPS，也没有发布 GitHub。'
}
