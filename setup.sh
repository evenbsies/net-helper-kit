#!/bin/sh
# SPDX-License-Identifier: MIT
# One-command interactive entry point. Review the source before running as root.
set -eu
umask 077
BASE=$(CDPATH='' cd -P -- "$(dirname -- "$0")" && pwd -P)
# shellcheck source=lib/common.sh
. "$BASE/lib/common.sh"
setup_help() {
    printf '%s\n' \
        'net-helper-kit — 一条命令交互式搭建' \
        '用法: ./setup.sh [--plan-only [新计划目录] | --help]' \
        '默认: Alpine 3.24 + OpenRC 上以 root 检查环境、生成计划并确认安装。' \
        '--plan-only [新计划目录]: 只生成离线计划，不安装、不联网；无路径时打开向导菜单。' \
        '必须事先准备可信的官方 Hysteria 2 二进制及官方 SHA256 digest。' \
        '共享域名首次官网注册/选名不能由 API 自动完成。' \
        '不会自动修改防火墙/NAT，不保证 64 MB 内存或公网连通性。'
}
case "${1:-deploy}" in
    --help|-h)
        [ "$#" -eq 1 ] || die '用法: ./setup.sh [--plan-only [新计划目录] | --help]'
        setup_help
        exit 0
        ;;
    --plan-only)
        [ "$#" -le 2 ] || die '用法: ./setup.sh --plan-only [新计划目录]'
        if [ "$#" -eq 2 ]; then
            exec "$BASE/wizard.sh" plan "$2"
        else
            printf '%s\n' '离线计划模式：请选择菜单 1 生成计划或 4 查看帮助；共享域名模式会被此入口禁止。'
            # A restricted offline menu avoids accidentally selecting networked
            # shared-plan from the normal guide in this explicitly offline mode.
            printf '%s\n' '1) 离线生成计划' '4) 查看帮助'
            ask_value '选择' '1'
            case "$ANSWER" in
                1)
                    ask_value '新计划目录（绝对路径）' "$HOME/net-helper-plan"
                    exec "$BASE/wizard.sh" plan "$ANSWER"
                    ;;
                4) exec "$BASE/wizard.sh" --help ;;
                *) die '离线模式仅支持 1 或 4；未联网、未安装' ;;
            esac
        fi
        ;;
    deploy)
        [ "$#" -eq 0 ] || die '用法: ./setup.sh [--plan-only [新计划目录] | --help]'
        ;;
    *) die '用法: ./setup.sh [--plan-only [新计划目录] | --help]' ;;
esac

# Refuse unsupported systems before dependency installation or output creation.
need_root_alpine
for item in wizard.sh lib/plan.sh lib/install.sh lib/shared_dns.sh openrc/nhk-dns openrc/nhk-hysteria; do
    [ -f "$BASE/$item" ] || die "源码不完整: $item"
done
for target in /etc/net-helper-kit /opt/net-helper-kit /etc/init.d/nhk-dns /etc/init.d/nhk-hysteria; do
    [ ! -e "$target" ] && [ ! -L "$target" ] || die "发现已有安装，拒绝覆盖: $target"
done
for account in nhk nhk-dns; do
    if id "$account" >/dev/null 2>&1 || grep -q "^$account:" /etc/group; then
        die "已有同名用户或组，拒绝复用: $account；请先按 README 审查旧安装"
    fi
done
printf '%s\n' \
    '一条命令搭建：检查环境 → 准备依赖 → 生成计划 → 审阅 → 确认安装。' \
    '本工具安装 Hysteria 2 与 dnsmasq，不隐藏真实软件、协议或公网 IP。' \
    '请先准备官方 Hysteria 2 二进制和官方 SHA256 digest；脚本不自动下载可执行程序。' \
    '1) 使用已有域名或 IPv4' \
    '2) 使用已在 DuckDNS 官网注册的共享子域名'
ask_value '地址模式' '1'; address_mode=$ANSWER
case "$address_mode" in 1|2) ;; *) die '地址模式无效，未安装' ;; esac
ask_value '新计划目录（绝对路径，不可已存在）' "$HOME/net-helper-plan"; output=$ANSWER
valid_path "$output" || die '计划目录必须是安全的绝对路径'
[ ! -e "$output" ] && [ ! -L "$output" ] || die '计划目录已存在，拒绝覆盖'
[ -d "$(dirname -- "$output")" ] || die '计划目录的父目录不存在'
if [ "$address_mode" = 2 ]; then
    ask_value '新域名凭据目录（源码树外，不可已存在）' "$HOME/net-helper-domain"; profile=$ANSWER
    valid_path "$profile" || die '凭据目录必须是安全的绝对路径'
    [ ! -e "$profile" ] && [ ! -L "$profile" ] || die '凭据目录已存在，拒绝覆盖'
fi
confirm '将联网执行 apk add --no-cache openssl ca-certificates curl，安装或更新基础依赖。这些 apk 包不会在取消后续步骤或卸载项目时移除；此时尚未启动节点服务。'
apk add --no-cache openssl ca-certificates curl
if [ "$address_mode" = 2 ]; then
    "$BASE/wizard.sh" shared-plan "$output" "$profile"
else
    "$BASE/wizard.sh" plan "$output"
fi
verify_plan "$output"
printf '\n私有计划已生成并通过完整性检查: %s\n' "$output"
printf '%s\n' \
    '请审阅此目录的配置、证书、二进制来源以及 NAT UDP 内外端口映射。' \
    '接下来进入安装确认；如需暂停审阅，请在安装提示处输入非 YES 内容。' \
    '取消不会删除私有计划或基础 apk 包；共享模式下已更新的 DNS 也不会撤销。'
"$BASE/wizard.sh" apply "$output"
printf '%s\n' \
    '本地安装与服务进程检查已完成。' \
    '仍需从服务器外验证域名解析、NAT UDP 转发和客户端连接；这不是公网可达性保证。' \
    '客户端敏感文件位于 /etc/net-helper-kit/client.json，请勿公开。'
