# Remote Location 使用说明

这份说明面向当前这台 Mac 和已配对的 iPhone。日常使用不需要重新编译控制器、输入
Keychain 密码或重复输入六位配对码。

## 每次开始使用

1. 连接并解锁 iPhone，确认手机已开启开发者模式。
2. 在终端进入仓库并启动控制器：

   ```fish
   cd /Users/sayori/Desktop/remote-location
   rl-start
   ```

3. 保持这个终端窗口运行，打开 iPhone 上的 **Remote Location Learning**。
4. 等待 App 顶部四项状态就绪：

   - `Local Network Permission`：`Allowed`
   - `Controller Link`：`Trusted controller connected`
   - `Active Test Device / Xcode`：`Ready`
   - `Injection Backend`：`devicectl ready`

终端显示新的六位码是正常的备用配对信息。已信任的 iPhone 会自动连接，不需要输入该码。

## 设置模拟地址

1. 在 App 中打开 **Choose Location**。
2. 在地图上移动到目标位置。
3. 点地图中央蓝色 `+`，把地图中心保存为 `Selected Location`。
4. 点右上角 **Done** 返回主页面。
5. 点 **Apply Selected Location**。
6. 等待 `Applied Simulation` 变为已应用，并确认 `Verified Simulation` 完成验证。
7. 打开 QQ、地图或其他目标 App 检查位置。

也可以使用地点搜索或手动输入经纬度。选择地址只会更新待选位置；只有点击
**Apply Selected Location** 才会真正修改系统提供给其他 App 的测试位置。

## 停止使用

先在 App 中点 **Stop Simulation**，然后回到终端按 `Control-C`。终端会再执行一次安全的
幂等清理。即使 App 已经关闭，也可以运行：

```fish
cd /Users/sayori/Desktop/remote-location
rl-reset
```

## 首次配置或控制器代码更新后

正常情况下不需要运行这一节。首次配置，或终端提示
`The controller source changed after installation` 时，执行：

```fish
cd /Users/sayori/Desktop/remote-location
direnv allow
rl-install
```

如果 macOS 出现 Keychain 窗口，输入 Mac 登录密码并选择 **始终允许**。安装器会保留现有
控制器身份和手机信任；失败时会恢复旧的控制器与安装元数据。

## 检查环境

遇到无法连接、按钮变灰或手机不就绪时，先运行只读检查：

```fish
cd /Users/sayori/Desktop/remote-location
rl-doctor
```

按失败项给出的恢复提示处理。常见情况如下：

- **找不到 iPhone**：重新连接数据线，解锁手机，确认双方仍互相信任。
- **Controller Link 未连接**：确认 `rl-start` 的终端仍在运行，并保持 App 在前台片刻。
- **Apply 按钮为灰色**：先选择位置，并等待 Controller Link 与 Injection Backend 就绪。
- **控制器源码已变化**：运行一次 `rl-install`，不要改用 `swift run`。
- **App 无法启动或签名过期**：打开 `RemoteLocation.xcodeproj`，选择已连接的 iPhone，
  在 Xcode 中重新 Build & Run。Personal Team 签名通常需要定期重新安装。
- **换新手机或清除了 App Keychain**：运行 `rl-start`，把终端显示的当次六位码输入 App，
  只需重新配对一次。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `rl-start` | 启动可信控制器；默认运行一小时 |
| `rl-start --seconds 86400` | 最长运行一天 |
| `rl-reset` | 清除可能仍在生效的模拟位置 |
| `rl-doctor` | 只读检查 Xcode、iPhone、签名和控制器状态 |
| `rl-install` | 首次安装或源码变化后更新稳定签名控制器 |

