# Abaqus UMAT Skills

一套面向 Codex 的 Abaqus UMAT/VUMAT 专项 skills，覆盖本构机制路由、返回映射、张量接口、状态事务、损伤审计、木材连续损伤、空间正则化、切线验证和分层验收。

**这是公开净化版。** 仓库不包含书籍、论文全文、PDF、课程逐字材料、视频时间码、OCR 文本、第三方 Fortran 源码、附件、ODB/INP 工程包或内部研究语料。

## 项目目标

这组 skills 不是一份“万能 UMAT”，而是一套问题路由与审计工作流。每个 skill 只负责一个明确机制边界，避免把不同本构角色混装，例如：

- 不把 Hill48 等效应力直接塞进 J2 径向返回；
- 不把 Tsai-Wu 失效判据当成塑性返回残差；
- 不把 `JOB_COMPLETED`、单张云图或弹性 `DDSDDE` 当作一致性证明；
- 不把不同 `PROPS/STATEV` 布局当成可直接重启的同一 ABI；
- 不在局部求解失败后提交半更新的应力、状态或能量。

## 25 个 skills

| 类别 | Skill | 主责 |
|---|---|---|
| 总路由 | `umat-update-mechanism-router` | 隔离屈服、流动、硬化、失效、损伤与客观率 |
| 表示 | `abaqus-tensor-voigt-adapter` | `NDI/NSHR/NTENS`、Voigt、剪切因子、材料轴与旋转历史 |
| 接口 | `umat-props-statev-contract` | `PROPS/STATEV/SDV` 的版本化位置契约与 restart 迁移 |
| 状态 | `umat-transactional-state-update` | trial/committed、原子提交与完整回滚 |
| 失败 | `umat-failure-cutback-protocol` | 局部失败分类、`PNEWDT` 与宿主 cutback 握手 |
| 隐式积分 | `cpa-implicit-return-mapping` | 一般小应变 CPA/CPPM、`F/G`、`Delta lambda` 与局部残差 |
| J2 | `j2-isotropic-hardening-radial-return` | 3D 小应变关联 J2 加标量各向同性硬化径向返回 |
| Hill48 | `hill48-yield-calibration-applicability-audit` | 参数语言、材料轴、角向拓扑与可表达性审计 |
| 显式交点 | `explicit-alpha-yield-intersection` | 弹性路径的首个物理屈服交点 `alpha` |
| 显式子步 | `explicit-adaptive-substepping` | embedded Euler 接受/拒绝与局部步长控制 |
| 漂移 | `explicit-yield-drift-correction` | 屈服面漂移检查、联合修正与回滚 |
| 物理域 | `constitutive-domain-stabilization-audit` | 近零分母、低围压与稳定化模型变更审计 |
| Tsai-Wu 参数 | `tsai-wu-parameter-audit` | 强度、交互系数、材料坐标与阈值约定 |
| Tsai-Wu 状态 | `tsai-wu-damage-state-machine` | 触发、方向归因、损伤演化、事件和删除状态机 |
| 软化 | `softening-objectivity-audit` | 增量、网格、特征长度与耗散能客观性 |
| 语义调试 | `umat-semantic-debugging` | 源码完整性、Fortran 形式、数组边界与宿主数据流 |
| 切线 | `ddsdde-finite-difference-audit` | 对完整离散更新映射逐列有限差分审计 |
| 验证 | `umat-hierarchical-validation` | 算子到材料点、单元体、切线和边值问题的证据矩阵 |
| 木材机制 | `wood-cdm-mechanism-router` | 分流木材压缩塑性、拉剪损伤、删除与离散裂纹 |
| 木材热力学 | `wood-cdm-thermodynamic-closure` | 自由能、驱动力、不可逆条件、耗散和卸载闭包 |
| 木材状态 | `wood-cdm-multimode-state-machine` | L/R/T 与剪切模式的并发触发、历史、原子提交和回滚 |
| 木材算子 | `wood-cdm-damaged-operator-closure` | 多方向损伤的六维刚度/柔度、耦合项和极限状态 |
| 木材正则化 | `wood-cdm-spatial-regularization-router` | 裂带、非局部、梯度和黏性路线及多网格证据门 |
| 木材非局部架构 | `wood-cdm-abaqus-nonlocal-architecture-router` | UMAT、UMATHT、UEL 与全局邻域字段的信息闭包 |
| 木材方向场 | `wood-fiber-orientation-field-pipeline` | 多源方向数据到积分点正交 L/R/T 的可追溯管线 |

## 推荐使用顺序

```text
机制路由
  -> 表示与 PROPS/STATEV 契约
  -> 专用更新器或损伤状态机
  -> trial/committed 事务与失败协议
  -> 材料点和单元级验证
  -> DDSDDE 有限差分审计
  -> 网格、增量、能量与边值问题验收
```

具体问题通常只激活一项主责 skill，再按该 skill 的“相关 skills”路由组合相邻审计，不应一次套用全部 25 项。

## 安装

每个一级目录都是一个独立 skill。可以克隆整个仓库后选择性复制，也可以用 Codex 的 skill installer 安装单个目录。

示例：

```powershell
python C:\Users\<you>\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py `
  --repo xvchujin/umat-skill `
  --path j2-isotropic-hardening-radial-return
```

安装后重新开始一个 Codex 任务，使 skill catalog 重新加载。

## 验证公开内容

跨平台 Python 入口：

```bash
python tools/update_skill_manifest.py
python tools/verify_public_release.py
git diff --check
```

Windows PowerShell 入口提供同一发布门：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\update-skill-manifest.ps1
powershell -ExecutionPolicy Bypass -File .\tools\verify-public-release.ps1
python .\tools\verify_public_release.py
git diff --check
```

验证器会检查：

- 25 个 skill 是否齐全且名称与 frontmatter 一致；
- 每个 skill 是否保留明确的“相关 skills”路由章节；
- 是否混入禁止的文档、媒体、归档、Abaqus 作业或源码文件；
- 是否存在构建目录、转录引用、时间码、外部相对链接、Markdown 引文块或异常大文件；
- 每个 skill 目录是否只包含允许的公开文件。
- 整个公开发布是否只包含明确允许的根文件、发布工具和 25 个 skill 元数据文件。

`SKILL_MANIFEST.tsv` 记录公开 skill 文件的相对路径、字节数和 SHA-256。发布验证会逐行重算并比对清单，避免清单过期或被替换。

修改任何 skill 后，按以下顺序更新：

先生成清单，再运行 Python 和 PowerShell 两套验证器，最后执行 `git diff --check`。两套实现必须对 skill 数、文件数和 manifest 数给出一致结果。

## 语言与发布工具

GitHub Languages 图由 Linguist 生成，Markdown、YAML 和 TSV 通常不进入编程语言百分比。早期版本只有两份可识别的 PowerShell 发布脚本，因此页面显示 PowerShell 100%，并不表示 skill 正文是 PowerShell。

仓库现在同时提供有实际用途的 Python 和 PowerShell 工具：

- Python：跨平台生成 `SKILL_MANIFEST.tsv` 并执行公开发布验证，适合 Linux、macOS、Windows 和 CI；
- PowerShell：保留 Windows 原生入口，并与 Python 检查同一版权 allowlist 和完整性合同。

语言比例只是实现文件的字节统计，不是质量指标；仓库不会为了改变百分比添加无功能占位代码。

## 版权与许可

本仓库采用 [MIT License](LICENSE) 开源许可发布；公开内容边界见 [PUBLICATION_POLICY.md](PUBLICATION_POLICY.md)。

## 工程免责声明

这些 skills 是建模、实现和验证的工作流，不是经过认证的材料模型，也不替代 Abaqus 官方接口文档、材料试验、独立代码审查或项目级验证。任何用于工程决策的 UMAT 都应在目标 Abaqus 版本、单元类型、材料轴、参数范围、增量范围和网格范围内重新验证。
