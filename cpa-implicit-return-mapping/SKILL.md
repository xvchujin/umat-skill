---
name: cpa-implicit-return-mapping
description: |
  当用户实现/审查一般小应变 CPA/CPPM，问题落在 signed F_trial、Δλ、separate F/G、non-associated flow、硬化或 local yield residual 时调用。先按几何路由：小应变关联 J2+标量各向同性硬化默认交 `j2-isotropic-hardening-radial-return`，已有 J2 CPA 的线性化审查/算法对比仍可用本 skill；Hill48/non-AFR 或一般 F≠G 严禁移植 J2 固定方向与 3G。Tsai-Wu 损伤不用；事务污染与预算耗尽分别组合事务/失败协议。
---

# CPA 隐式返回映射与 Δλ 联合状态更新

## I — 方法论骨架 (Interpretation)

CPA 把一次塑性材料更新写成材料点内部的残差求解，而不是一次公式代入。
先按屈服几何、关联性和未知量结构选择更新器；不要因为算法都“回到屈服面”就把 CPA、CPPM 与 J2 径向特例合并。
把小应变、各向同性弹性、关联 J2、标量各向同性硬化视为可沿试偏应力固定方向降成 `q_trial-3GΔγ-σy=0` 的专用分支；满足这些条件时调用专门 J2 skill。
把 Hill48、non-AFR、压力相关屈服和一般 `F≠G` 保留为独立 `n=∂F/∂σ`、`m=∂G/∂σ` 的联合线性化；不得借用 J2 的 `3G`、固定径向方向或 `Δγ=Δepbar` 归一化。
对光滑单面可在 CPA 当前点线性化或按已推导的 CPPM 最近点条件求解；对尖点/多面问题显式建立活动集或转专门算法，不在不可微点伪造唯一梯度。
先从已提交状态生成弹性试算态，以屈服残差决定弹性接受或塑性回映。
塑性分支在当前迭代态评价 `F`、屈服梯度 `∂F/∂σ`、流动方向 `∂G/∂σ` 和硬化导数。
每轮一阶线性化只给出一个增量修正，并非有限步长下的严格恒等式。
同一轮 `Δλ` 必须同步驱动应力和全部关联内变量，再以更新后的联合状态重算残差。
关联流动时才可令 `∂G/∂σ=∂F/∂σ`；理想塑性时才可删去硬化项。
收敛协议必须同时定义残差尺度、容差、最大迭代、非有限数/病态分母检查以及回滚出口。
局部残差收敛只证明材料点一致性；返回切线与 Abaqus 全局 Newton 收敛仍须另行审计。

---

## A2 — 触发场景 (Future Trigger)

### 用户会在什么情境下需要这个 skill?

1. 要把带屈服面、流动法则和硬化律的小应变塑性模型写进 UMAT。
2. 局部回映残差振荡、停滞、出现 NaN，或只靠减小全局增量才能继续。
3. 从理想塑性扩展到硬化或非关联流动，不确定哪些公式和状态必须同步改变。
4. 代码中已有试应力与 `Δλ`，但缺少尺度化收敛、迭代上限、回滚和失败出口。
5. 已声明 `F≤0` 为弹性域，却用 `|F_trial|` 决定是否进入塑性，或无界局部循环把域错误、残差停滞和 cutback 混在一起。
6. 需要判断 CPA、CPPM、J2 radial return 或尖点活动集谁主责，避免从一个特例复制局部分母。
7. Hill48/non-AFR 模型已有独立 yield/potential 参数集，需要构造 `n≠m` 的更新和一致性残差。

### 语言信号 (用户的话里出现这些就应激活)

- “怎么写 CPA / cutting-plane return mapping?”
- “trial stress 在屈服面外，Δλ 怎么迭代？”
- “non-associated flow 时 dF 和 dG 怎么放？”
- “yield residual 不降 / local iteration stuck”
- “F_trial≤0 为什么还进入塑性 / signed yield branch”
- “DO WHILE(.TRUE.) 只有减小全局增量才能跑”
- “理想 Mises 改成 hardening 要改哪些项？”
- “CPA vs CPPM vs radial return 怎么选？”
- “Hill48/non-AFR 能不能继续用 J2 3G denominator?”

### 与相邻 skill 的区分

- 与 `j2-isotropic-hardening-radial-return` 的区别：若模型严格属于小应变、关联 J2、各向同性弹性与标量各向同性硬化，后者利用几何把问题降为固定方向标量残差并主责表格查询/径向修正；本 skill 不与它争抢特例调用。
- 与 `hill48-yield-calibration-applicability-audit` 的区别：后者先审 Hill48 参数语言、材料轴、AFR/non-AFR 和模型可表达性；模型成立后，本 skill 才处理一般 `F/G` 回映，不负责用求解器补救错误模型族。
- 与 `explicit-alpha-yield-intersection` 的区别：本 skill 求塑性一致性的 `Δλ`；显式技能只定位总应变路径首次到达屈服面的比例 `α`。
- 与 `ddsdde-finite-difference-audit` 的区别：本 skill 生成并收敛应力/状态更新；后者把这一完整更新器当黑箱审计返回 Jacobian。
- 与 `umat-transactional-state-update` 的区别：本 skill 处理 CPA 方程、`Δλ` 和局部残差；后者处理任意更新器的 trial/committed 原子提交与回滚。
- 若题面已出现“失败迭代部分改写 `STATEV`、下一次调用读到坏历史”，事务污染已是当前问题，必须把 `umat-transactional-state-update` 与本 skill 同时激活，而不是只在动作里顺带说回滚。
- 与 `umat-failure-cutback-protocol` 的区别：本 skill 定义 CPA 内部有限迭代和失败条件；后者在局部恢复耗尽后负责 `PNEWDT` 与宿主重试握手。
- 与 `constitutive-domain-stabilization-audit` 的区别：已知 CPA 内的 `J2`/分母有限性守卫属于本 skill；只有准备以钳制、人工黏聚、压力平移等方式改变可容许域或本构时，才把域审计作为当前 skill。
- 与 `tsai-wu-damage-state-machine` 的区别：本 skill 用 `Δλ` 满足塑性一致性；Tsai-Wu `e` 只触发非塑性失效/损伤状态机，不进入 CPA 回映。
- 与 `umat-semantic-debugging` 的区别：已知是 CPA 的带符号弹塑分支、`Δλ` 方程或局部残差协议时，本 skill 主责；只有算法契约已明确而实际变量/实参错接时，才由后者定位。
- 与 `umat-hierarchical-validation` 的区别：本 skill 解决一次材料点更新；后者组织从算子到边值问题的证据链。
- 与 `umat-update-mechanism-router` 的区别：路由器只判断应进入哪类更新分支；确定为一般隐式 `F/G` 塑性后，本 skill 才构造并收敛局部方程。

---

## E — 可执行步骤 (Execution)

1. **声明模型与符号契约**
   - 先列出屈服几何、弹性各向同性/各向异性、关联性、硬化变量数、光滑/尖点和运动学，形成“CPA / CPPM / J2 径向特例 / 专门活动集”路由表。
   - 若且仅若满足小应变、关联 J2、各向同性弹性、标量各向同性硬化并能证明试偏应力方向固定，且任务只是实现该模型，停止本通用流程并转 `j2-isotropic-hardening-radial-return`；若任务明确审查既有 J2 CPA 或比较 CPA/CPPM，则继续，但写明为何不采用径向标量默认路线。
- 否则列出 `F(σ,q)`、`G(σ,q)`、全部内变量 `q`、演化律、应力符号、屈服函数正负约定、Voigt/工程剪切约定、单位和物理可容许域。当前约定采用 `F≤0` 为弹性可容许域。
   - 对每个算子写明输入形状、输出形状和解析/数值导数来源；只有有证据时才声明 `G=F` 或某硬化项为零。
   - 完成标准：路由决定有逐项假设证据；继续 CPA 时能从契约唯一写出残差、`n=∂F/∂σ`、`m=∂G/∂σ` 和每个内变量对 `Δλ` 的更新，不存在未说明的 J2 特例省项。

2. **保存提交态并构造弹性试算**
   - 深拷贝增量初的 `σ_n` 与全部 `q_n`，计算 `σ_trial=σ_n+De·Δε`，再按已声明符号约定评价带符号的 `F_trial` 与尺度化阈值 `tol_F`。
- 在当前 `F≤0` 约定下，`F_trial≤tol_F` 且物理域合格时走弹性出口；只有 `F_trial>tol_F` 才以试算态初始化塑性迭代。禁止用 `|F_trial|≤tol_F` 作为弹塑性分支条件，因为显著负值属于屈服面内而非塑性超越。
   - 完成标准：屈服面内和容差内侧的弹性分支不修改塑性历史；塑性分支尚未覆盖 committed 快照。

3. **在当前迭代态组装 CPA 修正**
   - 每轮都用当前 `σ_k,q_k` 重算 `F_k`、`n_k=∂F/∂σ`、`m_k=∂G/∂σ`、硬化导数与内变量演化系数。
- 按当前模型重新推导分母符号与收缩次序；计算前检查单位、有限性和相对尺度，禁止把未经重推的固定小数、J2 `3G` 或固定试偏应力方向直接移植到 Hill48/non-AFR。
   - 遇到尖点或多面同时激活时停止单梯度 CPA，建立活动集/半光滑残差或转专门算法；不得用任选一个法向继续。
   - 完成标准：所有项在同一迭代点评价，分母远离配置的奇异阈值，且 `Δλ_k` 为有限数。
   - 失败路径：分母病态、状态越界或出现 NaN/Inf 时，不提交候选态，转步骤 5。

4. **用同一 `Δλ_k` 联合更新并重算残差**
   - 同步得到 `σ_{k+1}` 与全部 `q_{k+1}`；非关联模型使用独立 `m_k` 与势参数，硬化模型按已声明归一化更新历史量，不默认 `Δλ=Δepbar`。
   - 重新评价尺度化残差、物理域和二级不变量；记录残差是否下降。必要的阻尼或线搜索必须作为显式策略，而非静默截断。
   - 完成标准：候选状态有限、物理可接受，且残差达到容差或相对前一轮有可判定改进。

5. **执行有限收敛与失败协议**
   - 当尺度化残差达标且状态约束满足时退出；否则在最大迭代数内继续。
   - 若残差停滞/恶化、迭代超限或状态非法，恢复步骤 2 的完整 committed 快照，输出首个失败原因，并转交局部重试/`PNEWDT` 协议。
   - 完成标准：循环只能以“收敛并可提交”或“已回滚且明确失败”结束，绝不存在无界 `DO WHILE(.TRUE.)`。

6. **原子提交并交出切线审计**
   - 收敛后一次性回写 `STRESS`、全部 `STATEV` 与诊断量；`DDSDDE` 必须标明是解析一致切线、近似切线还是暂用矩阵。
   - 完成标准：提交态重算残差仍合格；失败分支逐位等于调用初快照；随后用 `ddsdde-finite-difference-audit` 检查完整映射。

---

## B — 边界 (Boundary)

### 不要在以下情况使用此 skill

- 已确认是小应变关联 J2、各向同性弹性与标量各向同性硬化，并只需径向标量残差/表格硬化更新：使用 `j2-isotropic-hardening-radial-return`。
- 目标是显式路径交点、自适应显式子步或漂移修正：这些不是 CPA 局部回映。
- 目标是 Tsai-Wu 复材失效与刚度退化：Tsai-Wu 是失效判据，不是塑性模型，也不进入塑性一致性方程。
- 有限应变、黏塑性、损伤耦合或多面活动集问题尚未重新推导相应运动学、残差和线性化时，不可直接套用本小应变骨架。

## 相关 skills

- **depends-on**: `umat-transactional-state-update`——局部迭代必须保留 committed 快照，并只在联合残差通过后原子提交。
- **contrasts-with**: `explicit-alpha-yield-intersection`、`j2-isotropic-hardening-radial-return`——本 skill 求一般 `F/G` 联合一致性；前者求显式首交点 `α`，后者利用关联 J2 几何降成径向标量特例。
- **composes-with**: `umat-update-mechanism-router`、`hill48-yield-calibration-applicability-audit`、`ddsdde-finite-difference-audit`——先路由并核对模型语义，再对一般回映的完整 Jacobian 做数值审计。

---

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
