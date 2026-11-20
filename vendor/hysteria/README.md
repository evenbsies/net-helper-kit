# Hysteria 官方安装脚本快照

`install_server.sh` 是 Hysteria 官方安装脚本的原样快照，来源为官方脚本入口 [https://get.hy2.sh](https://get.hy2.sh)，该入口当前重定向到 `https://get.hy2.sh/install_server.sh`。快照于 2026-11-20 获取。

- SHA-256：`7eff77a205445d5a2f846b57433369e465bb767e5c228d2f3785012a6a5f3fc5`
- 官方说明：[Server Installation Script](https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/)
- 上游仓库的 MIT 许可文本保存在 [`LICENSE.md`](LICENSE.md)；脚本自身的 SPDX MIT 标识与 Aperture Internet Laboratory 版权声明也原样保留。本项目没有改写或重新许可上游代码。

## 适用范围

官方文档说明该脚本用于在常见 Linux 发行版上安装、升级或卸载 Hysteria 及其 systemd 服务，并明确列出 Alpine 为不支持的发行版。它只生成示例配置，仍需手动配置服务。

本项目主向导面向 Alpine 3.24 + OpenRC，因此**不会从 `setup.sh` 或 `wizard.sh` 调用此脚本**。不要在本项目支持的 Alpine 主机上运行它，也不要把它当作本项目部署步骤。若要在另一个受支持的 systemd 主机单独使用，先审阅脚本和上游文档；它需要系统级权限，并会安装或更新系统范围内的二进制及 systemd 单元。

在受支持的 systemd 主机上可手动运行：

```sh
sudo bash vendor/hysteria/install_server.sh
```

该文件是固定快照，不会自动跟随上游变化。更新本项目仓库（例如 `git pull`）只会取得仓库已提交的快照版本；要同步更新此文件，需审阅新的官方脚本、更新本文件记录和 SHA-256，并运行项目测试。校验记录见同目录的 `SHA256SUMS`。
