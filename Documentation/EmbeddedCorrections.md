# 相机内嵌校正数据

这是扩展独立镜头覆盖的研究入口，尚未成为产品矫正路径。已有原生支持和 Lensfun 标定继续按原规则使用，不把原片中出现校正字段直接视为可安全应用。

2026-10-21 对已有两份完整公开 Sony ARW 做了只读核查。来源、仓库条目、记录的 CC0 许可、固定 SHA256 和精简字段夹具位于 `Tests/Fixtures/Sony-embedded-metadata.json`。可运行：

```sh
python3 Tests/verify-sony-embedded-metadata.py
```

脚本只读取固定的可选公开原片，缺失时明确列出；不会生成照片、读取私人照片集合、修改 EXIF 或应用校正。它调用随源码提供的 ExifTool，只提取明确分组的厂家表、机型、文件类型和存储尺寸，不输出路径、GPS 或序列号。精简结果为 `Evidence/sony-embedded-source-verification.json`。

| 样本 | 当前源事实 |
| --- | --- |
| Sony A6000，仓库条目 1971 | SubIFD 含 11 个畸变节点、11 对色差节点和 11 个暗角节点；首元素分别为 11/22/11，剩余填充全零，实际数据在有符号 16 位范围内 |
| 同一 A6000 的 MakerNote 区 | 也有同名字段，但表示方式和部分数值与 SubIFD 不同，不能先丢掉分组再选择任意同名值 |
| A6000 存储与显影尺寸 | SubIFD 为 6048×4024；已验收显影/PXD 为 6000×4000。中心、有效区域、缩放及坐标方向需要明确对应，不能直接把存储尺寸当编辑画布 |
| Sony A200，仓库条目 2271 | 本次明确查询没有这套校正表。不能从另一机身或相似镜头补入 |

厂家表随原片携带，有机会补充数据库缺少的镜头或焦距/光圈状态，而不需要 Lightroom 安装或 Adobe 配置分发。是否真正扩大支持，必须由读取、数值算法与实际图像结果证明，当前两份源字段核查不计作新增镜头支持。

启用前还需完成以下验证：表结构和缺失/冲突拒绝；有效传感器区域与显影坐标对应；畸变和色差方向、中心及节点插值；线性光暗角响应及零表恒等；原生已处理时避免重复；独立数值对照；三项开关、强度、裁切和源绑定的可编辑保存；实际完整图像与宿主验收。不能仅凭表名生成曲线，也不能把有表等同于三项都有非零校正。

## 0.2.8 build 15 的原生读取与数值核心

`LensSonyEmbeddedSourceEvidence` 现在接入生产元数据读取的既有分组 ExifTool 调用。它只接受明确的 Sony ARW、CFA SubIFD、有效的整数尺寸、2–16 个节点及有符号 16 位系数；核对计数、零填充和各现存表的节点一致性。缺失某项会保持缺失，错误或冲突表不作为有效来源；同名 MakerNote 不能替代 SubIFD。原始数组保留在独立来源对象中，不被扁平化成任意同名拍摄参数，也不生成像素曲线。读取未增加 ExifTool 进程。

`LensSonyEmbeddedGeometryFactor` 是坐标无关的标量计算：依据记录节点，对畸变和红/蓝通道分别插值，再组合倍率；绿色作为色差参考通道。它尚未由产品渲染器调用。所有零几何表严格得到恒等倍率，未知/无效数据不会生成一个默认校正值。这个核心不定义图像中心、像素坐标、裁切变换或暗角增益。

72 组精确分数对照覆盖三个通道、两项开关、节点/中间值与端点延拓，最大数值误差为零。固定 [RawTherapee 源码快照](https://github.com/RawTherapee/RawTherapee/blob/7deb2754d1f31beff891063b476905d4093e8570/rtengine/lensmetadata.cc) 的相关方法另在开发临时目录编译，与同组分数参照一致。21 组无效来源、缺项独立性、非正几何倍率拒绝、真实 A6000/A200 的生产读取、原片哈希及现有 Lensfun 方案保持不变均通过。旧版生产读取对同一组测试有 4 项新增来源/尺寸观测要求未满足，新版为零；这不是旧版几何算法有 4 个错误。

`LensReadNativeCorrectionSupport` 使用公开 `CIRAWFilter.nativeSize` 和方向属性记录解码器观测，不渲染像素。A6000 原生尺寸为 6000×4000，A200 为 3872×2592。另用开发环境 LibRaw 观察 A6000：存储为 6048×4024、默认裁切前可见尺寸为 6024×4024、默认裁切为 6000×4000。尺寸相同不能证明相机表的校准坐标中心或裁切原点已对应；`pixelFrameVerified` 与 `renderingEnabled` 均保持 false。

## 仍需解决的参照差异

[darktable 4.6 的固定参照](https://github.com/darktable-org/darktable/blob/release-4.6.0/src/iop/lens.cc) 先在节点组合几何倍率再插值，RawTherapee 则分别插值再相乘。当前样本单项因子一致，两项同时使用时采样最大差为约 5.36×10⁻⁷；不能把这些实现视为逐位相同，更不能由此推断光学精度。

同一暗角表在归一化半径 1 的开发参照计算得到约 1.336 与 1.754 两个不同增益，响应及插值定义需要进一步验证。LensDock 尚未实现或选择其中任一相机表暗角增益，没有用已有场景亮度去决定哪个数值正确。现有 Lensfun 暗角和默认关闭规则不变。

证据见 `Evidence/build15-sony-source-model-verification.json`、`Evidence/sony-radial-upstream-oracle-verification.json`、`Evidence/sony-embedded-frame-observations.json` 和 `Evidence/build15-verification.json`。参照 GPL 源码与独立比较程序只保存在被忽略的开发临时目录，不链接或分发进产品；LibRaw/rawpy 也只是开发比较工具，不增加用户运行依赖。build 15 的 31 个常规组、192 组渲染、构建、隔离安装与部署检查通过，尚未更新研究宿主、重新做 GUI/保存/导出或生成新 DMG。已验收的 0.2.7 包保持原样。
