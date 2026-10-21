#!/bin/sh
# SPDX-License-Identifier: MIT
apply() {
    need_root_alpine
    need sha256sum; need mktemp
    # Do not adopt or overwrite any previous installation, even after uninstall.
    for target in /etc/net-helper-kit /opt/net-helper-kit /etc/init.d/nhk-dns /etc/init.d/nhk-hysteria; do
        [ ! -e "$target" ] && [ ! -L "$target" ] || die "目标已存在，拒绝覆盖: $target"
    done
    for account in nhk nhk-dns; do
        if id "$account" >/dev/null 2>&1 || grep -q "^$account:" /etc/group; then
            die "已有同名用户或组，拒绝复用: $account；若是先前失败/卸载遗留，请审查并手动移除未使用账号后重试"
        fi
    done
    verify_plan "$1"
    confirm '将安装 apk 依赖、创建两个服务账号及独立 OpenRC 服务。不会改系统 DNS、防火墙、NAT 或已有代理。计划必须由你信任的人生成；其中的二进制会以非 root 账号运行。'
    SNAPSHOT=$(mktemp -d /tmp/nhk-apply.XXXXXX)
    ETC_CREATED=no; OPT_CREATED=no; DNS_CREATED=no; HY_CREATED=no; SUCCESS=no
    trap 'apply_cleanup' EXIT
    trap 'exit 1' HUP INT TERM
    for item in $PLAN_FILES SHA256SUMS; do cp "$1/$item" "$SNAPSHOT/$item"; done
    verify_plan "$SNAPSHOT"
    # Package/account additions are deliberately not rolled back: they may be shared.
    apk add --no-cache dnsmasq ca-certificates openssl
    addgroup -S nhk
    adduser -S -D -H -G nhk -s /sbin/nologin nhk
    addgroup -S nhk-dns
    adduser -S -D -H -G nhk-dns -s /sbin/nologin nhk-dns
    [ "$(id -u nhk)" -ne 0 ] && [ "$(id -u nhk-dns)" -ne 0 ] || die '服务账号不能是 root'
    # Recheck targets after package installation and immediately before creation.
    for target in /etc/net-helper-kit /opt/net-helper-kit /etc/init.d/nhk-dns /etc/init.d/nhk-hysteria; do
        [ ! -e "$target" ] && [ ! -L "$target" ] || die "目标在安装期间出现，拒绝覆盖: $target"
    done
    mkdir /etc/net-helper-kit; ETC_CREATED=yes
    mkdir /opt/net-helper-kit; OPT_CREATED=yes
    chown root:nhk /etc/net-helper-kit
    chmod 751 /etc/net-helper-kit
    chmod 755 /opt/net-helper-kit
    for item in server.yaml dnsmasq.conf blocklist.conf server.crt server.key client.json node-uri.txt binary.sha256 tls-mode format-version SHA256SUMS; do
        cp "$SNAPSHOT/$item" "/etc/net-helper-kit/$item"
        chown root:root "/etc/net-helper-kit/$item"
        chmod 600 "/etc/net-helper-kit/$item"
    done
    for item in server.yaml server.crt server.key; do
        chown root:nhk "/etc/net-helper-kit/$item"
        chmod 640 "/etc/net-helper-kit/$item"
    done
    chmod 644 /etc/net-helper-kit/dnsmasq.conf /etc/net-helper-kit/blocklist.conf
    cp "$SNAPSHOT/hysteria" /opt/net-helper-kit/hysteria
    chown root:root /opt/net-helper-kit/hysteria
    chmod 755 /opt/net-helper-kit/hysteria
    # Verify architecture/major version using a non-root account, not root.
    su -s /bin/sh -c '/opt/net-helper-kit/hysteria version' nhk > "$SNAPSHOT/version" 2>&1 || die '二进制无法在此 Alpine/CPU 上运行'
    grep -Eq 'Version:[[:space:]]*v?2\.' "$SNAPSHOT/version" || die '需要官方 Hysteria 2 Linux 二进制'
    dnsmasq --test --conf-file=/etc/net-helper-kit/dnsmasq.conf
    # Exclusive creation avoids overwriting a concurrently created service.
    (set -C; cat "$BASE/openrc/nhk-dns" > /etc/init.d/nhk-dns); DNS_CREATED=yes
    (set -C; cat "$BASE/openrc/nhk-hysteria" > /etc/init.d/nhk-hysteria); HY_CREATED=yes
    chmod 755 /etc/init.d/nhk-dns /etc/init.d/nhk-hysteria
    rc-service nhk-dns start
    rc-service nhk-hysteria start
    sleep 3
    rc-service nhk-dns status
    rc-service nhk-hysteria status
    rc-service nhk-dns healthcheck || die 'DNS 应用进程未就绪'
    rc-service nhk-hysteria healthcheck || die 'Hysteria 应用进程未就绪'
    rc-update add nhk-dns default
    rc-update add nhk-hysteria default
    SUCCESS=yes
    printf '%s\n' '独立服务已启动。请从容器外测试 NAT UDP 连通和客户端远端域名解析。' \
        '客户端文件位于 /etc/net-helper-kit/client.json（root 只读，含密码）。' \
        '这是软内存优化配置，不保证在 64 MB 下不触发 OOM；请先小流量试运行。'
}
apply_cleanup() {
    code=$?
    trap - EXIT HUP INT TERM
    if [ "$SUCCESS" != yes ]; then
        printf '%s\n' '安装失败，清理本次创建的服务与文件；apk 包和服务账号保留。' >&2
        if [ "$HY_CREATED" = yes ]; then
            rc-service nhk-hysteria stop >/dev/null 2>&1 || :
            rc-update del nhk-hysteria default >/dev/null 2>&1 || :
            rm -f /etc/init.d/nhk-hysteria
        fi
        if [ "$DNS_CREATED" = yes ]; then
            rc-service nhk-dns stop >/dev/null 2>&1 || :
            rc-update del nhk-dns default >/dev/null 2>&1 || :
            rm -f /etc/init.d/nhk-dns
        fi
        [ "$ETC_CREATED" != yes ] || rm -rf /etc/net-helper-kit
        [ "$OPT_CREATED" != yes ] || rm -rf /opt/net-helper-kit
    fi
    rm -rf -- "$SNAPSHOT"
    exit "$code"
}
uninstall() {
    need_root_alpine
    [ -f /etc/net-helper-kit/format-version ] || die '未找到本项目安装标记'
    [ "$(cat /etc/net-helper-kit/format-version)" = 1 ] || die '安装标记不识别'
    confirm '将停止并移除本项目两个服务及 /opt/net-helper-kit；保留 /etc/net-helper-kit 私密配置、apk 包和服务账号。不会修改已有代理。'
    # Stop failure is not ignored: never remove binaries while a service is running.
    for service in nhk-hysteria nhk-dns; do
        if [ -f "/etc/init.d/$service" ]; then
            if rc-service "$service" status >/dev/null 2>&1; then rc-service "$service" stop; fi
            rc-update del "$service" default >/dev/null 2>&1 || :
            rm -f "/etc/init.d/$service"
        fi
    done
    rm -rf /opt/net-helper-kit
    printf '%s\n' '已卸载服务，配置保留在 /etc/net-helper-kit。重装前须由你备份并移走该目录。'
}
