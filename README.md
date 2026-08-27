# CineSwipe

CineSwipe 是一个仅支持 iPhone 竖屏的 SwiftUI 影视发现应用，最低支持
iOS 17。它使用 TMDB 获取电影和电视剧数据，并使用 SwiftData 在本机保存
想看、已看和 30 天临时跳过状态。

## 配置 TMDB

仓库不会保存真实 TMDB API Key。在 Xcode 中打开 Scheme 的 Run 配置，进入
Arguments，添加环境变量：

```text
TMDB_API_KEY=你的 TMDB v3 API Key
```

也可以在本地构建设置中定义 `TMDB_API_KEY`，工程会将其注入生成的
Info.plist。不要提交包含真实密钥的本地配置文件。

## 运行

1. 使用 Xcode 打开 `CineSwipe.xcodeproj`。
2. 选择 iOS 17 或更高版本的 iPhone 模拟器。
3. 确认已配置 `TMDB_API_KEY`，然后运行 `CineSwipe` Scheme。

应用不需要登录，不包含分析 SDK，也不会上传用户的片单状态。
