#!/bin/sh
# SPDX-License-Identifier: MIT
# Libraries are sourced by wizard.sh; never source untrusted plan files.
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少工具: $1"; }
ask_value() {
    printf '%s [%s]: ' "$1" "$2" >&2
    IFS= read -r ANSWER || die '输入中断'
    ANSWER=${ANSWER:-$2}
}
valid_port() {
    case "$1" in ''|*[!0-9]*|0*|??????*) return 1 ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
valid_ipv4() {
    printf '%s\n' "$1" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255 || (length($i)>1 && substr($i,1,1)=="0")) exit 1}'
}
valid_host() {
    [ "${#1}" -le 253 ] || return 1
    case "$1" in ''|*[!a-zA-Z0-9.-]*) return 1 ;; esac
    case "$1" in *[!0-9.]* ) ;; *) valid_ipv4 "$1"; return $? ;; esac
    printf '%s\n' "$1" | awk -F. 'NF<2 {exit 1} {for(i=1;i<=NF;i++) if(length($i)<1 || length($i)>63 || $i !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/) exit 1}'
}
valid_path() {
    case "$1" in /*) ;; *) return 1 ;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/..|*/./*|*/.|/) return 1 ;; esac
}
valid_sha() { [ "${#1}" -eq 64 ] && case "$1" in *[!0-9a-fA-F]*) false ;; *) true ;; esac; }
sha_file() { sha256sum "$1" | awk '{print $1}'; }
need_root_alpine() {
    [ "$(id -u)" -eq 0 ] || die '此操作需要 root'
    [ -f /etc/alpine-release ] || die '仅支持 Alpine Linux，不在本机执行安装'
    case "$(cat /etc/alpine-release)" in 3.24.*) ;; *) die '当前版本仅支持 Alpine 3.24.x' ;; esac
    need rc-service; need rc-update; need apk
    [ -d /run/openrc ] || die '未发现运行中的 OpenRC；不要在未初始化的容器里安装'
    [ -r /proc/self/status ] || die '需要已挂载 procfs，以检查应用进程健康状态'
}
confirm() {
    printf '%s\n输入 YES 继续: ' "$1" >&2
    IFS= read -r reply || die '输入中断'
    [ "$reply" = YES ] || die '已取消，未开始安装/卸载'
}
# Explicit list: no globbing, traversal or executable manifests.
PLAN_FILES='server.yaml dnsmasq.conf blocklist.conf server.crt server.key client.json node-uri.txt hysteria binary.sha256 tls-mode binding-mode bbr-profile format-version'
plan_listen_port() {
    awk '
        /^listen:/ {
            n++
            if ($0 !~ /^listen:[[:space:]]+0\.0\.0\.0:[0-9]+$/) bad=1
            else { p=$0; sub(/^listen:[[:space:]]+0\.0\.0\.0:/, "", p) }
        }
        END { if (n != 1 || bad || p == "") exit 1; print p }
    ' "$1/server.yaml"
}
verify_plan() {
    PLAN=$1
    valid_path "$PLAN" || die '计划目录必须是安全的绝对路径（不含空格或 ..）'
    [ -d "$PLAN" ] && [ ! -L "$PLAN" ] || die '计划目录不存在或是符号链接'
    for item in $PLAN_FILES SHA256SUMS; do
        [ -f "$PLAN/$item" ] && [ ! -L "$PLAN/$item" ] || die "计划缺少普通文件: $item"
    done
    [ "$(cat "$PLAN/format-version")" = 3 ] || die '不支持此计划格式'
    # Compare fresh canonical manifest rather than trusting manifest paths.
    actual=$(cd "$PLAN" && for item in $PLAN_FILES; do sha256sum "$item"; done)
    [ "$actual" = "$(cat "$PLAN/SHA256SUMS")" ] || die '计划完整性校验失败，请重新生成'
    expected=$(cat "$PLAN/binary.sha256")
    valid_sha "$expected" || die '无效二进制校验值'
    [ "$(sha_file "$PLAN/hysteria")" = "$expected" ] || die 'Hysteria 二进制 SHA256 不匹配'
    listen_port=$(plan_listen_port "$PLAN") || die 'server.yaml 的 listen 必须是唯一的 0.0.0.0:端口'
    valid_port "$listen_port" || die 'server.yaml 的 listen 端口无效'
    [ "$listen_port" -ne 5353 ] || die '5353 已保留给本地 DNS'
    binding_mode=$(cat "$PLAN/binding-mode")
    case "$binding_mode" in
        unprivileged) [ "$listen_port" -ge 1024 ] || die '低端口计划必须明确使用 capability 模式' ;;
        capability) [ "$listen_port" -lt 1024 ] || die '高端口计划不得请求 capability 模式' ;;
        *) die '无效的 binding-mode' ;;
    esac
    bbr_profile=$(cat "$PLAN/bbr-profile")
    case "$bbr_profile" in
        standard|conservative|aggressive) ;;
        *) die '无效的 BBR profile' ;;
    esac
}
