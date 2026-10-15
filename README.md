# LensDock · 镜头坞

**保留 RAW 的 Pixelmator 镜头矫正预览版（0.2.1）。** 为原生镜头矫正尚不支持的照片，补充有可靠标定依据的畸变、横向色差和暗角补偿；原生支持时自动跳过补充畸变与色差，并保留默认关闭的“额外去暗角”。

当前是可安装、已做本机测试的预览版。**尚未达到 Lightroom Classic 的镜头覆盖范围或光学等效验收，也不是 Apple 官方扩展。** Pixelmator 没有提供本项目所需的公开 RAW 编辑插件接口，因此安装程序从用户自己安装的兼容应用建立独立本机宿主，在其菜单与可编辑效果中集成 LensDock。原厂应用保留；分发包不包含 Pixelmator 应用或框架。

## 安装与使用

1. 在 Apple 芯片 Mac 上自行安装 **Pixelmator Pro Creator Studio 4.3，build 3.0.75**。其他版本、普通版和 Intel Mac 尚未适配。
2. 打开含内嵌矢量高清背景的 DMG，将 `LensDock.app` 拖到“应用程序”，打开 LensDock。
3. 点击“安装预览宿主”。版本、四个关键二进制的 SHA256、签名和 arm64 加载结构全部通过才会安装；不需要管理员权限。
4. 点击“打开 Pixelmator”，打开 RAW 并选中 RAW 图层，进入 **镜头矫正 → 打开镜头矫正…**。
5. 查看推荐量，独立选择三项功能，点击“应用到 RAW”。重新匹配恢复本次建议；普通重新打开会重新检测支持并保留已保存的手动选择及拍摄参数覆盖。

宿主安装位置为 `~/Applications/Pixelmator LensDock Preview.app`。含 LensDock 效果的 PXD 请通过此宿主打开，原厂应用没有该自定义滤镜。原 RAW 保留在文档资源中，无 TIFF 中转。主滑块显示实际最大校正量（短边位移百分比、色差像素、暗角 EV），详细设置保留标定倍率与焦距、光圈、距离；修改参数不改写原片 EXIF。

**分发状态：** 当前仅 ad-hoc 签名，未做 Developer ID 签名或 Apple 公证。已验证本机安装与启动；下载到其他 Mac 后可能受 Gatekeeper 限制，不能视为正式的一键分发版。如系统允许且用户决定运行，可使用系统设置提供的“仍要打开”流程。正式发布需要补齐签名、公证和另一台 Mac 的安装验证。构建目标为 macOS 26.0，实机验证环境为 macOS 27.2；macOS 26 尚未实测。

## 原生优先与推荐规则

“能够读取 RAW / 镜头名称”不等于“能够矫正”。本项目针对每张原片调用公开的 `CIRAWFilter.isLensCorrectionSupported` 检测矫正能力，而不是根据相机解码清单推断。

| 当前状态 | LensDock 行为 |
| --- | --- |
| 原生支持 | 补充畸变、色差自动跳过，保留原生 RAW 开关当前状态，不偷偷打开它 |
| 原生支持，另有有效暗角标定 | 显示“额外去暗角”，默认关闭、推荐 0 EV，可手动试调；不把完整标定当成已测得的残余暗角 |
| 原生支持，缺少独立暗角标定 | 保留选项和原因，但禁用补偿；没有新效果可应用时禁用“应用到 RAW” |
| 原生不支持，独立配置唯一且有效 | 使用 Lensfun 的实际标定；缺少或数学上为零的某项不生成该项补偿 |
| 不明支持状态、歧义配置、未知镜头或越界焦距 | 明确报告，停止添加补偿，不用“相似镜头”代替 |

公共原生支持标志并不提供逐项畸变/色差/暗角能力明细；跳过补充几何是本项目防止重复矫正的策略，不是逐项原生光学效果等效的证明。

对原生不支持的照片，边角内容与高光检测只能约束可靠镜头标定的补偿强度。孤立暗物体、逆光和复杂边角不能当成暗角证据；不确定时保留关闭状态，提供保守试用量或 0。无有效标定时不生成畸变、色差或提亮曲线。三个开关和用户强度分别随效果保存。

## 覆盖与验证

数据库来自 Lensfun 公共数据库提交 `43f9e001ab66c4fcdd4f400463f13b72f94b2288`，有 1057 个相机条目、1571 个镜头条目。数据库衍生的 1566 个身份/插值样本中 1537 个匹配成功，29 个因相机或镜头歧义拒绝；另有 5 个条目没有可测试标定/兼容相机。这些数字**不是实际 RAW 支持率，也不是光学准确率**。

上述数量对应已发布的 `v0.1.0-preview`。当前开发源码增加了相机地区名称、镜头与卡口联合证据、传感器校准版本选择及 XML 原始别名保留；自动目录样本匹配为 1563 / 1566。另可从 LX3 原始 RW2 边界字段确认拍摄模式。开发版面板提供可搜索的“选择配置…”：确认相机模式和镜头校准，重新计算建议，再通过“应用到 RAW”保存。实际 Nikon PXD 已验证手选配置保存、关闭和重新打开；内嵌原 RAW 不变。详见 [匹配规则与目录核查](Documentation/Matching.md)。正常照片会自动读取并填入焦距、光圈及已记录的对焦距离；缺少 FNumber 但存在拍摄 ApertureValue 时也会自动恢复；Canon 仅记录距离区间时保留并显示区间，不冒充单一实测距离；只有确实缺失的信息才需补全，光圈未知不启用暗角补偿。本地 CR2、NEF、CR3 自动读取回归及 NEF 实际界面填值已验证。这些改进纳入 0.2.0 候选包；GitHub 原有 0.1.0 发布资产不变。新版宿主的完整保存/重开验收仍未完成。

已验证真实 Canon 40D CR2、Nikon D70 NEF 的独立匹配，以及 Canon EOS R50 V / RF-S14–30mm CR3 的原生优先界面。96 组原生渲染组合覆盖三项开关、部分及超完整强度、线性与 sRGB 传递、密集和紧凑映射；另有边角内容、高光、零标定、不误替代镜头、源绑定与设置序列化测试。本机安装程序已实际完成安装、启动和菜单检查，原厂关键文件哈希不变。

另新增两份完整公开 LX3 RAW（1:1、4:3）的自动模式、焦距/光圈、原生优先及实际解码预览核查；十八组测试通过。照片不进入源码包，仍未补齐宿主保存/重开或光学验收。

0.2.1 另以完整 Sony A6000、Olympus E-M5、Sony A200 RAW 对照公开 Exiv2 记录，三份均自动填入拍摄焦距和光圈，E-M5 的已记录对焦距离也自动填入。A6000/E-M5 自动生成对应配置；A200 镜头仍无法唯一匹配，单列为覆盖缺口。已排除 Sony 根据对焦位置推算的 Composite 距离，保留直接记录的距离与明确远距回退；十九组测试、96 个原生渲染组合通过，详见 `Evidence/public-capture-metadata-verification.json`。既有 0.2.0 候选包保持原样。

实际 A6000 RAW 已完成自动填值、校正应用、首次保存、关闭和重开，原 RAW 字节与三项选择保留。修复了宿主重算白平衡派生坐标时的浮点舍入误判；原片、主白平衡参数、尺寸及颜色空间仍严格校验。**性能尚不适合正式交付：本轮 2400 万像素 PXD 达约 1.37 GB，全尺寸映射生成较慢。** 见 `Evidence/a6000-reopen-verification.json`；未完成无损导出、所有 RAW 或光学等效验收。

详见 [验收与限制](Documentation/Validation.md)、[兼容接口](Documentation/Compatibility.md) 和 `Evidence/`。历史证据记录对应当时构建，不要把旧 SHA256 当成当前包；当前包清单在 `Distribution/`。

## 源码结构与构建

- `Sources/Native/`：匹配、渲染、RAW 资源桥接、源绑定、推荐、原生面板与效果保存。
- `Sources/Installer/`：不依赖 Python 的 macOS 安装/启动程序。
- `Compatibility/`：已验证 Pixelmator 版本、关键文件哈希与部署契约。
- `Resources/`：效果模板、镜头数据库、ExifTool 源码运行资源。
- `Vendor/`：独立动态库、版权许可、对应上游源码和构建来源。
- `Tests/`、`Evidence/`：维护中的测试与精简验证结果。无原片、PXD 或临时缓存。
- `Scripts/`：源码构建、测试、DMG 打包。生成物在 `Build/` 和 `Distribution/`，不进入源码提交。

开发需 Apple 芯片 Mac、Xcode 命令行工具和 Python 3；**用户运行不需要 Python 或 Lightroom**。

```sh
python3 Scripts/build.py
python3 Scripts/test.py
python3 Tests/verify-installer-installation.py
python3 Scripts/audit_catalog.py --run
python3 -m pip install -r Scripts/dmg_requirements.txt
python3 Scripts/package.py
python3 Scripts/verify_dmg.py
```

版本由 `Version.json` 统一管理。打包产物位于 `Distribution/<版本>-preview/`，已有同名资产会被拒绝覆盖；安装程序核对宿主版本、模块登记哈希与实际模块字节，旧版会提示保留文档后重新安装，不自动替换宿主。

原生渲染测试需本机兼容 Pixelmator 的 PTFoundation；它不会被复制进仓库。实际 RAW 专项可在本地 `Tests/PrivateRAW/` 放置 `Canon40D.CR2`、`NikonD70.NEF`、`CanonR50V.CR3`；这些文件被 Git 忽略，默认测试不会凭空生成真实 RAW 证据。依赖源码归档有 SHA256 清单，见 `Vendor/Sources/upstream-manifest.json`。

## 卸载与数据保留

退出预览宿主后，将 `LensDock.app` 和 `~/Applications/Pixelmator LensDock Preview.app` 移到废纸篓即可。PXD、原片、原厂应用和 Lightroom 目录不属于卸载内容。先保留含自定义效果的文档和兼容宿主；原厂应用无法提供同一个自定义滤镜。

本项目不传输照片或运行遥测。RAW 原始资源读取到独立临时目录用于元数据/支持检测后清理；保存的效果含标定、设置与检测预览，以便编辑和核验。预览版的文件体积和性能仍待优化。
