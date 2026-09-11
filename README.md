# 云映

[![License](https://camo.githubusercontent.com/44e26a8116bb6f791a2574a317f5eb2c75555a92f954123353f990fbee1f28ef/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f4c6963656e73652d417061636865253230322e302d7265642e737667)](https://github.com/briltec/flutter_Pokedex/blob/master/LICENSE) [![License](https://camo.githubusercontent.com/2b0f0abcb5a51eb4cc8321bd5a5e6eb16390950eaee6f9d4f2243af2facbe483/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f4c6963656e73652d4d49542d7265642e737667)](https://github.com/briltec/flutter_Pokedex/blob/master/LICENSE)

一个基于 Flutter 框架开发的轻量级图片备份工具，使用 WebDAV 或 S3 协议实现跨平台、简洁高效的本地图片云端备份方案。

## 📸 应用截图

> 应用持续更新中，新版本界面可能稍有变化

<div align="center">
  <div style="display: flex; justify-content: center; gap: 20px;">
    <img src="assets/images/example1.jpg" alt="用户登录界面" width="25%" />
    <img src="assets/images/example2.jpg" alt="用户仪表盘界面" width="25%" />
  </div>
</div>

## ✨ 特性

📱 跨平台支持：借助 Flutter，轻松运行于 Android、iOS、Windows、macOS、Linux

☁️基于 WebDAV 协议：兼容主流云存储服务（如坚果云、Nextcloud、自建服务器等）

🎯 简洁优雅的用户界面：专注体验，操作直观易上手

⚙️ 功能持续迭代中，致力于打造高效实用的备份体验

## ☁️使用教程

以坚果云[坚果云](https://www.jianguoyun.com/#/)为例子,官方提供每月1Gb的上传流量,3Gb的下载流量,无限空间

且下载不限速

1. [生成应用授权密码](https://help.jianguoyun.com/?p=2064)
2. 点击右上角输入账号与授权密码即可

### S3 同步

在「连接设置」中选择 **S3**，填写 Endpoint、Region、Bucket、Access Key ID 和 Secret Access Key，然后点击「保存并开始备份」。临时凭证还需填写 Session Token。

- AWS 示例：Endpoint 为 `https://s3.us-east-1.amazonaws.com`，Region 为 `us-east-1`；请按存储桶的实际区域修改。
- S3 兼容服务：填写服务商提供的 Endpoint 和 Region。自建服务可填写包含端口的地址，例如 `http://192.168.1.10:9000`。
- 默认启用路径式访问（`Endpoint/Bucket`）；如服务商要求虚拟主机式访问（`Bucket.Endpoint`），关闭该开关。Endpoint 不要重复包含存储桶名。
- 存储桶需预先创建，凭证需具有 `s3:ListBucket` 及 `MyPhotos/*` 下的 `s3:GetObject`、`s3:PutObject`、`s3:DeleteObject` 权限。
- 原图保存在 `MyPhotos/`，缩略图保存在 `MyPhotos/.thumbs/`。支持增量备份、分页同步、云端预览、下载到本地和删除云端备份。
- S3 的备份记录按 Endpoint、Bucket 和 Access Key 隔离；切换回 WebDAV 会恢复原有 WebDAV 备份记录。切换不会搬迁或删除旧云端文件。
- 配置沿用应用现有的本地偏好存储方式；当前未使用系统密钥库。大文件采用流式单次上传，暂不支持分片上传及断点续传。

签名实现参考 [AWS Signature V4](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-header-based-auth.html)，列表分页参考 [ListObjectsV2](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html)。

## 🎯 项目目标

### 核心功能（Key Features）

- [x] 增量备份：仅上传新增或变动的图片，节省流量与存储资源
- [ ] 自动备份：接入系统媒体库监听，实现插入即备份
- [x] 相册预览：在 App 内浏览已备份图片，支持分类与搜索
- [x] 端云协同：本地与云端数据状态同步，避免重复冗余
- [ ] 扩展更多备份接口：支持百度网盘、阿里云盘等主流平台

### 其他规划（Other Plans）

- [ ] 关于页面：展示项目介绍、开源协议、作者信息等
- [X] 动效优化：增强交互反馈，提升整体 UI 质感与流畅度
- [ ] 我再再测试一手呢

## 📄 许可证

此项目基于 AGPL-3.0 许可证进行许可，详情请参阅 [LICENSE](https://github.com/ZhuJHua/moodiary/blob/develop/LICENSE) 文件。

## 💖 鸣谢

- 感谢 Flutter 团队提供出色的框架。
- 特别感谢开源社区的宝贵贡献。
- 尤其感谢Gemini对项目的辅助
