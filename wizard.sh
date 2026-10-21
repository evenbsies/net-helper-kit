#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
umask 077
BASE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/common.sh
. "$BASE/lib/common.sh"
# shellcheck source=lib/plan.sh
. "$BASE/lib/plan.sh"
# shellcheck source=lib/install.sh
. "$BASE/lib/install.sh"
# shellcheck source=lib/shared_dns.sh
. "$BASE/lib/shared_dns.sh"
help() {
    printf '%s\n' 'net-helper-kit — 网络配置向导（Hysteria 2 + 轻量 DNS 过滤）' \
        'guide  打开分步菜单（默认）' \
        'plan [新目录]  离线生成私有安装计划，不修改系统' \
        'shared-plan /新计划目录 /新凭据目录  引导注册 DuckDNS 后更新解析并生成计划' \
        'dns-update /凭据目录  确认后更新已注册的共享子域名' \
        'apply /绝对/目录  在 Alpine/OpenRC 上确认后安装' \
        'status | export | uninstall' \
        '共享域名首次登录和选名需在官网完成；不保证第三方免费服务稳定性。'
}
guide() {
    printf '%s\n' 'net-helper-kit 分步向导' \
        '本工具安装 Hysteria 2 和 dnsmasq。名称简洁不等于隐藏协议或服务器 IP。' \
        '1) 使用已有域名或 IPv4，离线生成计划' \
        '2) 使用共享子域名：先官网注册，再绑定解析并生成计划' \
        '3) 更新已有共享子域名解析' \
        '4) 查看完整命令帮助' \
        '提示：生成计划不会安装；审阅后需单独执行 apply。'
    ask_value '选择' '2'; choice=$ANSWER
    case "$choice" in
        1|2)
            ask_value '新计划目录（绝对路径，不要放进源代码目录）' "$HOME/net-helper-plan"; destination=$ANSWER
            if [ "$choice" = 2 ]; then
                ask_value '新域名凭据目录（源代码树外的绝对路径）' "$HOME/net-helper-domain"; profile=$ANSWER
                shared_plan "$destination" "$profile"
            else
                plan "$destination"
            fi
            ;;
        3)
            ask_value '已有域名凭据目录' "$HOME/net-helper-domain"
            dns_update "$ANSWER"
            ;;
        4) help ;;
        *) die '选择无效，未执行任何操作' ;;
    esac
}
case "${1:-guide}" in
    guide) [ "$#" -le 1 ] || die '用法: guide'; guide ;;
    plan) [ "$#" -le 2 ] || die '用法: plan [新目录]'; plan "${2:-$PWD/private-output}" ;;
    shared-plan) [ "$#" -eq 3 ] || die '用法: shared-plan /新计划目录 /新凭据目录'; shared_plan "$2" "$3" ;;
    dns-update) [ "$#" -eq 2 ] || die '用法: dns-update /凭据目录'; dns_update "$2" ;;
    apply) [ "$#" -eq 2 ] || die '用法: apply /绝对/计划目录'; apply "$2" ;;
    status)
        need_root_alpine
        rc-service nhk-dns status; rc-service nhk-dns healthcheck
        rc-service nhk-hysteria status; rc-service nhk-hysteria healthcheck
        ;;
    export) need_root_alpine; printf '%s\n' '客户端敏感文件: /etc/net-helper-kit/client.json' '/etc/net-helper-kit/node-uri.txt（勿公开）' ;;
    uninstall) uninstall ;;
    help|--help|-h) help ;;
    *) die '未知命令；使用 --help' ;;
esac
