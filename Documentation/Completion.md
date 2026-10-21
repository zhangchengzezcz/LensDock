# 完整目标验收

目标仍是：在 Pixelmator 内完成保留 RAW 的镜头矫正，并拥有与 Lightroom Classic 一样全面的自动匹配。通用版本检查和公开 Issues 是兼容策略，不能代替镜头覆盖或光学效果验收。2026-10-20 的结论是 **未完成，目标保持 active**；不能仅补完弹窗就标记整个任务完成。

| 要求 | 当前证据与判定 |
| --- | --- |
| 内置操作、保留 RAW 与可编辑参数、无 TIFF 中转 | 4.3 独立宿主有真实菜单与 RAW 图层效果。build 11 新反射桥接已在实际 A6000 上完成应用/保存/退出/重开，RAW 哈希不变；build 12 复测引用通过。原厂应用保留，非官方插件 |
| 独立运行，无 Lightroom/Python 用户运行依赖 | 原生安装器、Lensfun/ExifTool 与独立库随包；完整隔离安装通过。可选开发比较脚本读取本地 LCP，不参与产品运行，也不复制 Adobe 校准数据 |
| Lightroom Classic 等量自动匹配 | **未证明**。build 11 公共库为 1057 个相机、1572 个镜头记录，目录样本 1564/1567。它们不是实际 RAW 支持率，不能与 LCP 文件数直接比较；缺少逐光学身份、机身/模式、标定范围和原生处理并集的等效证明 |
| 正确光学算法，不凭内容制造畸变 | 使用可靠身份对应的 Lensfun 标定；已有插值、恒等/边界、方向与渲染回归。仍缺足够实拍光学基准，不能把坐标计算正确当作所有镜头都正确 |
| 三项独立选择，推荐数值可上下调整 | 192 组渲染组合与实际新桥接面板通过；D 显示 2.752%，可下调至 2.477%、上调至 3.302%，推荐按钮复位；90% D、100% TCA、暗角关闭、裁切开启保存重开保留 |
| 原生矫正支持时跳过几何，额外暗角保留且默认关闭 | 真实 CR3 与原生优先回归；根据 CIRAWFilter 的矫正能力判断。支持与用户是否开启原生开关分开，不冒充测得残余暗角 |
| 暗角与内容边角检测，避免不必要提亮 | 独立标定、对称衰减/孤立暗物体/高光等受控回归。复杂自然内容及真实残余暗角的全面可靠性未证实 |
| 自动填写光圈、焦距、距离 | 多份实际 CR2/NEF/CR3/ARW/ORF 及 821 张 CR3 对照。未知/区间/远距回退明确区分；未记录光圈不启用暗角 |
| 透明边修复，保留可逆选择与原始数据 | build 11 新桥接实际 PXD 与重开、RAW 哈希及 6000×4000、16 位 Display P3 PNG 已复测：全图 alpha=65535，导出不改变设置或 RAW；没有全镜头光学等效证明 |
| Pixelmator 4.3+、Apple 芯片 macOS 26+，通用检查而非逐版本适配 | 安装器签名/结构/导出接口检查、运行时值布局与序列化自检、7 个 arm64 二进制部署契约通过。本机 4.3 / 27.2 基线；未来行为以检查与 Issue 反馈处理，不声称逐机实测 |
| 打开照片自动检查，首次可忽略以后提示 | build 11/12 实际照片自动提示、忽略、后台继续检查、手动重查和恢复通过，build 11 正常退出/重启后忽略保留。build 12 使用异步文档附属面板；同文档恢复后不立刻重复提示 |
| 菜单可用、界面清楚 | 占位菜单已移除，真实主矫正面板、滑块推荐标记及照片画布已截图检查。系统提示的截图工具仍返回空白，AX 正文/按钮完整且可操作；用户已直接目视确认文字与按钮显示正常 |
| 应用速率与内存 | 已有紧凑格式、懒数值表、按需平面与系统分块；源摘要和进程自检结果复用。已有 24 MP 数据与基准，不能推广至全部 Mac、低内存设备或长期负载 |
| 高清背景 DMG，图片真正内嵌 | 0.2.5 候选镜像内矢量 PDF、源图移开及异名只读挂载验证通过；桌面副本与清单摘要一致。该包不是完整目标的最终验收版 |
| 整理源码、公开 GitHub 和 Issues | 已公开仓库，问题模板、源码提交、506 文件候选源码包逐文件核对与六项草稿附件核对通过。RAW、PXD、原厂应用不分发 |
| 用户可直接安装分发 | 候选安装与打包通过；仍为 ad-hoc 签名，未公证。当前没有有效 Developer ID Application 签名身份；其他设备的下载/Gatekeeper 流程未验证 |

主要证据：`Evidence/constrained-crop-saved-document-verification.json`、`Evidence/constrained-export-16bit-verification.json`、`Evidence/generic-compatibility-0.2.5.json`、`Evidence/installer-0.2.5-verification.json`、`Evidence/three-corrections-verification.json`、`Evidence/native-priority-verification.json`、`Evidence/public-capture-metadata-verification.json` 及 `Distribution/0.2.5-preview/` 的候选交付清单。各证据的版本、范围和未测项仍有效，不能跨版本冒用。

新实机证据见 `Evidence/build11-live-raw-verification.json`、`Evidence/build11-export-16bit-verification.json`、`Evidence/photo-open-notice-ui-verification.json` 与 `Evidence/build12-verification.json`。下一步仍包括独立自动匹配覆盖、实拍光学证据、正式签名分发。F810 只有格式约束的受控路由，没有真实 F810 RAF；只读参考名称统计不证明 Lightroom 等效，也不为缺失镜头生成猜测曲线。

系统提示的最后外观判定已由用户直接确认，记录在 `Evidence/notice-user-visual-confirmation.json`；这项确认不改变镜头覆盖、广泛光学验证与正式分发仍未完成的结论。

0.2.7 build 13 又修复镜头身份比较与等价小数写法，保留型号标识并移除单个词查询候选的自动接受路径。同组旧版 11 项失败、新版零失败；30 个常规组、192 组渲染及全库 1564/1567 回归通过，无新增目录拒绝或指定版本差异。两组小尺寸配置约 123–127 ms，未证明完整应用提速。本轮新宿主打开 PXD 又遇到文件面板按钮禁用，没有新增 GUI 保存/导出通过声明。0.2.6 冻结交付不变，见 `Evidence/build13-verification.json`；不能把身份修复当成 Lightroom 等量覆盖完成。

2026-10-21 的 build 14 已完成新的实际 A6000 自动匹配、选择界面身份核对、应用、首次保存、关闭/重开及 6000×4000、16 位 Display P3 PNG 导出。全图 24M 像素不透明，原 RAW 和导出前后 PXD 哈希不变，档案无手选覆盖。配置选择与引擎共用身份判断，旧版 3 处预选不一致已修复；30 个常规组、192 组渲染、全库及隔离安装继续通过。该实机结果补充了 build 13 的未验收项，不能推广为所有文件面板问题根因已解决或所有镜头光学等效。Sony 内嵌校正表仅完成源事实核查，尚未用于产品。完整 Lightroom 覆盖、广泛光学验证和正式签名分发仍未完成；目标继续 active。证据见 `Evidence/build14-verification.json` 与 `Documentation/EmbeddedCorrections.md`。
