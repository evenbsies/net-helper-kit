#!/bin/sh
# SPDX-License-Identifier: MIT
# DuckDNS shared subdomain integration. Source this file; do not execute it.
# All network access in this file is explicit: shared_plan and dns_update only.

_shared_die() { die "$@"; }
_shared_base_dir() { printf '%s' "${BASE:-}"; }
_shared_safe_path() {
    _sp=$1
    valid_path "$_sp" || return 1
    [ "$_sp" != / ] || return 1
    case "$_sp" in *//*|*/) return 1 ;; esac
    # Check every existing prefix, not only the final object: this blocks
    # symlinked parents and aliases into/out of the source tree.
    while [ "$_sp" != / ]; do
        [ ! -L "$_sp" ] || return 1
        _sp=$(dirname -- "$_sp") || return 1
    done
}
_shared_in_project() {
    _b=$(_shared_base_dir)
    [ -n "$_b" ] || return 1
    case "$1" in
        "$_b"|"$_b"/*) return 0 ;;
        *) return 1 ;;
    esac
}
_shared_overlap() {
    case "$1" in "$2"|"$2"/*) return 0 ;; esac
    case "$2" in "$1"|"$1"/*) return 0 ;; esac
    return 1
}
_shared_slug() {
    [ "${#1}" -ge 1 ] && [ "${#1}" -le 63 ] || return 1
    case "$1" in *[!a-z0-9-]*|-*|*-) return 1 ;; esac
}
_shared_public_ipv4() {
    valid_ipv4 "$1" || return 1
    awk -F. 'function n(a,b,c,d){return a*16777216+b*65536+c*256+d}
      { x=n($1,$2,$3,$4); if ($1==0 || $1==10 || $1==127 || $1>=224 ||
        ($1==100 && $2>=64 && $2<=127) || ($1==169 && $2==254) ||
        ($1==172 && $2>=16 && $2<=31) || ($1==192 && $2==168) ||
        ($1==192 && $2==0 && $3==0) || ($1==192 && $2==0 && $3==2) ||
        ($1==192 && $2==88 && $3==99) || ($1==198 && $2==18) ||
        ($1==198 && $2==19) || ($1==198 && $2==51 && $3==100) ||
        ($1==203 && $2==0 && $3==113) || x==4294967295) exit 1 }' <<EOF
$1
EOF
}
_shared_stty_restore() {
    stty "$_shared_stty_state" 2>/dev/null || true
    trap - HUP INT TERM
}
_shared_read_secret() {
    if [ -t 0 ] && [ -t 2 ] && command -v stty >/dev/null 2>&1; then
        printf '%s' "$1" >&2
        _shared_stty_state=$(stty -g 2>/dev/null) || return 1
        stty -echo 2>/dev/null || return 1
        trap '_shared_stty_restore' HUP INT TERM
        if IFS= read -r ANSWER; then _r=0; else _r=$?; fi
        _shared_stty_restore
        printf '\n' >&2
        [ "$_r" -eq 0 ] || return 1
    else
        printf '%s' "$1" >&2
        if IFS= read -r ANSWER; then :; else return 1; fi
    fi
}
_shared_confirm() {
    printf '%s\n输入 YES 继续（将修改远程 DNS，更新不可原子回滚）: ' "$1" >&2
    IFS= read -r _answer || return 1
    [ "$_answer" = YES ]
}
_shared_field() {
    awk 'NR == 1 { value = $0; next } { bad = 1 } END { if (bad || value == "") exit 1; print value }' -- "$1"
}
_shared_uuid() {
    printf '%s' "$1" | grep -Eq '^[0123456789abcdefABCDEF]{8}-[0123456789abcdefABCDEF]{4}-[0123456789abcdefABCDEF]{4}-[0123456789abcdefABCDEF]{4}-[0123456789abcdefABCDEF]{12}$'
}
_shared_profile_validate() {
    _p=$1
    _shared_safe_path "$_p" || _shared_die 'profile 必须是安全的绝对路径'
    _shared_in_project "$_p" && _shared_die '拒绝从项目源码树读取 profile'
    [ -d "$_p" ] && [ ! -L "$_p" ] || _shared_die 'profile 必须是非符号链接目录'
    [ "$(stat -c '%u' -- "$_p" 2>/dev/null)" = "$(id -u)" ] || _shared_die 'profile 所有者必须是当前用户'
    [ "$(stat -c '%a' -- "$_p" 2>/dev/null)" = 700 ] || _shared_die 'profile 目录权限必须为 700'
    for _n in domain token ipv4; do
        _f=$_p/$_n
        [ -f "$_f" ] && [ ! -L "$_f" ] || _shared_die "profile 文件无效: $_n"
        [ "$(stat -c '%u' -- "$_f" 2>/dev/null)" = "$(id -u)" ] || _shared_die 'profile 文件所有者无效'
        [ "$(stat -c '%a' -- "$_f" 2>/dev/null)" = 600 ] || _shared_die 'profile 文件权限必须为 600'
    done
    _d=$(_shared_field "$_p/domain") || _shared_die 'profile domain 内容无效'
    _t=$(_shared_field "$_p/token") || _shared_die 'profile token 内容无效'
    _i=$(_shared_field "$_p/ipv4") || _shared_die 'profile ipv4 内容无效'
    _shared_slug "$_d" || _shared_die 'profile domain 无效'
    _shared_public_ipv4 "$_i" || _shared_die 'profile IPv4 必须是可路由公网地址'
    _shared_uuid "$_t" || _shared_die 'profile token 格式无效'
    printf '%s\n%s\n%s\n' "$_d" "$_t" "$_i"
}
_shared_update_values() {
    _d=$1; _t=$2; _i=$3
    need curl
    _resp=$(printf 'url = "https://www.duckdns.org/update"\ndata = "domains=%s&token=%s&ip=%s"\n' "$_d" "$_t" "$_i" |
      curl --disable --get --silent --show-error --fail --proto '=https' --connect-timeout 10 --max-time 30 --retry 2 --noproxy '*' --config - 2>/dev/null) || return 1
    [ "$_resp" = OK ]
}
shared_plan() {
    _out=$1; _profile=$2
    _shared_safe_path "$_out" || _shared_die '输出目录必须是安全的绝对路径'
    _shared_safe_path "$_profile" || _shared_die 'profile 必须是安全的绝对路径'
    _shared_in_project "$_out" && _shared_die '输出目录不能位于项目源码树'
    _shared_in_project "$_profile" && _shared_die 'profile 不能位于项目源码树'
    _shared_overlap "$_out" "$_profile" && _shared_die '输出目录和 profile 不能相同或互相嵌套'
    [ ! -e "$_out" ] && [ ! -L "$_out" ] || _shared_die '输出目录已存在，拒绝覆盖'
    [ -d "$(dirname -- "$_out")" ] || _shared_die '输出目录的父目录不存在'
    [ ! -e "$_profile" ] && [ ! -L "$_profile" ] || _shared_die 'profile 已存在，拒绝覆盖'
    [ -d "$(dirname -- "$_profile")" ] || _shared_die 'profile 的父目录不存在'
    printf '%s\n' 'DuckDNS 官方注册/登录和手动选择子域名：' 'https://www.duckdns.org' '公开 API 仅用于更新，不能自动申请子域名。' >&2
    ask_value '已在 DuckDNS 手动选择的单个 slug（仅小写字母、数字、中横线）' ''; _d=$ANSWER
    _shared_slug "$_d" || _shared_die 'slug 无效'
    ask_value 'NAT 面板显示的公网 IPv4（不自动探测）' ''; _i=$ANSWER
    _shared_public_ipv4 "$_i" || _shared_die 'IPv4 必须是可路由公网地址，禁止私有/回环/链路本地/组播/保留地址'
    _shared_read_secret 'DuckDNS token（输入不回显）: ' || _shared_die '读取 token 失败'; _t=$ANSWER
    _shared_uuid "$_t" || _shared_die 'token 必须是 UUID'
    _shared_confirm "将更新 ${_d}.duckdns.org -> $_i，token 不会显示" || _shared_die '已取消，未修改远程 DNS'
    _shared_update_values "$_d" "$_t" "$_i" || _shared_die '无法确认远程结果；未保存 profile，请官网检查后重试'
    (umask 077 && mkdir -- "$_profile" && printf '%s\n' "$_d" > "$_profile/domain" && printf '%s\n' "$_t" > "$_profile/token" && printf '%s\n' "$_i" > "$_profile/ipv4" && chmod 700 "$_profile" && chmod 600 "$_profile/domain" "$_profile/token" "$_profile/ipv4") || _shared_die 'profile 保存失败；远程 DNS 可能已更新，请官网检查后重试'
    if NHK_HOST_DEFAULT="$_d.duckdns.org" "$BASE/wizard.sh" plan "$_out"; then
        printf '%s\n' 'DuckDNS 已更新且本地计划生成成功。' >&2
    else
        printf '%s\n' '向导失败；远程 DNS 已更新，profile 已保留。请使用普通 plan 输入正确域名，或用 dns-update 更新已有 profile 后重试；shared-plan 不会覆盖原 profile。' >&2
        return 1
    fi
}
dns_update() {
    _profile=$1
    _values=$(_shared_profile_validate "$_profile") || return 1
    _d=$(printf '%s\n' "$_values" | sed -n '1p'); _t=$(printf '%s\n' "$_values" | sed -n '2p'); _i=$(printf '%s\n' "$_values" | sed -n '3p')
    printf '%s\n' "将更新 ${_d}.duckdns.org -> $_i（token 不显示）" >&2
    _shared_confirm '确认执行 DuckDNS 更新' || _shared_die '已取消，未修改远程 DNS'
    _shared_update_values "$_d" "$_t" "$_i" || _shared_die '无法确认远程结果；本地 profile 未改动，请官网检查后重试'
    printf '%s\n' 'DuckDNS 更新成功；这不代表 DNS 已传播或 UDP 服务可达。' >&2
}
