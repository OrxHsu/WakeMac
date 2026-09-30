# 安全问题报告

当前维护版本为 **1.0.x**。已修复的问题会在后续版本和更新记录中说明。

涉及辅助服务越权、任意命令执行、认证绕过或私人数据泄露的问题，请使用 GitHub 的 **[私密漏洞报告](https://github.com/OrxHsu/WakeMac/security/advisories/new)**，不要在公开 Issue 中发布利用细节、凭据或私人日志。

报告请包含受影响版本、macOS／芯片信息、复现步骤、影响及最小证明。普通界面或设备兼容问题请走 [Issues](https://github.com/OrxHsu/WakeMac/issues/new/choose)。个人维护项目无法承诺固定响应时间。

WakeMac 不读取或保存登录密码，不自动解锁，不修改系统密码要求。合盖服务需要系统批准，并仅允许同一 Apple 开发者签名的主程序调用固定电源接口。电源控制和签名限制见 [README](README.md#合盖服务与权限)。

正式发布的 v1.0.0（构建 31） 压缩包提供 SHA-256 校验文件，使用 Apple Development 签名，尚未做 Developer ID 公证。请仅从本仓库 Releases 下载；不要为运行应用关闭 Gatekeeper 或 SIP。
