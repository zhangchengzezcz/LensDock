# Lightroom 实际几何对照

2026-10-31 在用户授权后，通过 Lightroom Classic 的正常界面创建独立目录，仅以 Add 导入固定 CC0 样本 `ILCE-6000.ARW` 的工作副本。没有修改用户照片的修改设置。原始样本和工作副本在导出后 SHA256 均为 `ce8b4957281a817d52a07a691e2468567b6c78223bd0b514ffc1c65b002b8d89`。清理时已通过正常界面恢复桌面、`未命名导出`、JPEG 70%、sRGB/8 位，并使用“完成”保存；最终窗口 URL 已确认回到用户的 `Lightroom Catalog.lrcat`。

本对照只观测 Sony E 18–55mm OSS 的一张实际照片与 Adobe 渲染的接近程度，不能证明所有镜头覆盖、光学真值或厂家通用坐标契约。参考图、RAW 和目录均留在忽略的 `Build/Development/LR-Optical-Reference/`，不会打包到产品；没有提取或分发 Adobe 的标定系数。Lightroom 仅是开发参考，不是产品运行依赖。

## 必须区分的色差状态

Lightroom 的内置配置文件信息弹窗明确显示：

> Sony ILCE-6000 / E 18-55mm F3.5-5.6 OSS  
> 此原始文件包含内置的镜头配置文件，用于纠正色差。已自动将配置文件应用到此图像。

因此，即使普通的 `AutoLateralCA=0` 且 `LensProfileEnable=0`，基线仍带有自动内置色差处理。**不能将该基线称为完全未矫正，也不能用它验收色差关闭或厂家 TCA。** 此次只比较开启额外配置文件产生的几何变化，暗角设为零。

## 导出与测量

两张导出均为 6000×4000、16 位、sRGB PNG，无缩放、输出锐化、水印、HDR 或 Content Credentials；导出 XMP 验证 `HasCrop=false`、`CropConstrainToWarp=0`。

| 本地目录 | 几何状态 | SHA256 |
| --- | --- | --- |
| `Exports/Baseline-built-in-CA` | `LensProfileEnable=0`，仍含上述内置 CA | `8a1e65f39f873281ad6b5601edacd1a857a06f7d84720bc0426bbbcef50b75eb` |
| `Exports/Geometry-D100-V0` | 自动匹配 Adobe Sony E 18–55mm OSS，D=100、V=0 | `2261cc681f58372d0aa7d1c7dffd090b74b66faca37621f4ad4709bd45d875ad` |

`Tests/observe-lightroom-sony-geometry.py` 是可选开发脚本，需要 numpy、scipy、Pillow。它校验这两张固定导出的摘要和元数据，再使用四分之一、二分之一分辨率的亮度图进行空间测量，不作颜色/曝光精度比较。每个区域先用归一化相关排除低纹理或歧义峰，再独立以三次插值和局部仿射精化位移，不用 Sony 曲线选择区域。已知位移和恒等对照均通过。

随后按预先固定的网格棋盘分成训练与验证区域，只拟合全局等比缩放和二维平移作为构图干扰项。Sony 的节点数、值、方向和强度保持不变，不拟合成 Adobe 曲线。产品不会使用这里拟合的参数。

| 测量分辨率 | 接受区域（训练/验证） | 只缩放和平移的验证 RMS | Sony 6000×4000 候选验证 RMS | Sony 候选验证 P95 |
| --- | --- | --- | --- | --- |
| 1500×1000 | 72（40/32） | 10.356 原图像素 | 0.884 原图像素 | 1.849 原图像素 |
| 3000×2000 | 67（35/32） | 9.836 原图像素 | 0.868 原图像素 | 1.904 原图像素 |

6024×4024 居中候选的验证 RMS 分别为 0.985、0.967 像素，6048×4024 居中候选分别为 1.045、1.027 像素。差异不足以将最接近 Adobe 的候选宣布为厂家通用坐标。接受区域覆盖约 0.096–0.903 半对角线半径，但分布不均，半尺寸测量的上方两个象限仅 5、4 个区域；没有声称全部边角均已验证。

本结果支持 Sony 表的几何形状与此场景 Lightroom 变化接近。仍未证明厂家的校准空间、其他机型/画幅/焦距、真实直线恢复、TCA 或暗角效果。`pixelFrameVerified=false`、产品自动厂家表路径关闭的状态保持不变。下一步应取得独立样本和坐标约定证据，再接入真实提供者、RAW 源绑定与可编辑保存；不能只凭这一组误差启用所有相机。

完整的区域、拒绝情况、固定条件、导出元数据和工具摘要见 `Evidence/lightroom-sony-geometry-observation-0.25.json` 与 `Evidence/lightroom-sony-geometry-observation-0.5.json`。复测命令：

```sh
python Tests/observe-lightroom-sony-geometry.py --scale 0.25
python Tests/observe-lightroom-sony-geometry.py --scale 0.5
```

参考文件不存在或改变时脚本拒绝运行，不静默改用用户图库的其他照片。
