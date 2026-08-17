---
name: j2-isotropic-hardening-radial-return
description: |
  为 Abaqus UMAT 实现/审查 3D 小应变关联 J2/von Mises+标量硬化时调用；信号：signed F_trial、radial return、Δγ、3G+H、hardening table、q≈0/local Newton。只主责径向标量特例。不用于非 3D 小应变/VUMAT、Hill48/non-AFR、随动/混合硬化、黏塑性或损伤；一般 F/G 转 cpa-implicit-return-mapping，参数/STATEV ABI 转 umat-props-statev-contract，trial 污染组合事务更新，切线专审转 FD audit。
---

# 三维小应变 J2 标量硬化径向返回

## I — 方法论骨架 (Interpretation)

只在三维小应变、各向同性线弹性、关联 J2/von Mises 屈服和单一标量硬化 `sigma_y(epbar)` 闭合时，使用本流程。

从 committed 状态构造全弹性试应力，先评价带符号 `F_trial=q_trial-sigma_y(epbar_n)`，再决定弹性或塑性活动集。

在屈服分支之前只计算偏应力范数，不要计算 `s/||s||`；纯静水或零增量必须无 `0/0`。

利用 J2 偏应力几何固定试方向，把塑性更新降为一个标量残差：

`R(Delta gamma)=q_trial-3G*Delta gamma-sigma_y(epbar_n+Delta gamma)=0`

每轮都以候选 `epbar` 从同一硬化区间同步查询 `sigma_y` 与 `H`，使用 `dR/dDelta gamma=-(3G+H)`。

仅对通过尺度化残差、有限性、变量域、分母和迭代预算的 `Delta gamma` 重建应力、全部历史、能量和切线。

把 legacy 13 槽、8 槽 F90 和 1 槽线性硬化实现视为共享物理骨架的三个不兼容接口版本，不要复用未绑定版本的 restart 或 SDV 脚本。

把局部成功与原子提交绑定；迭代耗尽、NaN、负增量或非法表格都必须保持 committed 状态不变。

把塑性切线标为“候选”，直到完整离散更新的逐列有限差分证明其导数契约。

---

## A2 — 触发场景 (Future Trigger)

### 在以下场景调用

1. 要为 C3D8/C3D8R 等三维小应变实体编写关联 J2 表格/线性标量硬化 UMAT。
2. 已有 `q_trial`、`Delta gamma`、`3G+H` 或径向缩放，但弹塑分支、硬化查询或重建顺序不明确。
3. 纯静水/零初始应力出现 `0/0`、NaN，平台硬化或表格拐点使 Newton 异常。
4. 卸载/再加载、纯剪或多轴路径中 `epbar`、塑性应变、耗散或屈服残差不一致。
5. 两份代码都声称 J2 各向同性硬化，但硬化对顺序、SDV 数量或剪切历史语义相反。

### 识别以下中英文信号

- “J2/von Mises isotropic hardening UMAT”
- “radial return / 径向返回 / closest radial correction”
- “`F_trial=q_trial-sigma_y`、`Delta gamma`、`3G+H`”
- “hardening table interpolation and slope H”
- “pure hydrostatic gives NaN / q is zero”
- “unloading-reloading、PEEQ vs SDV、local Newton not converged”

### 与相邻 skill 分工

- 一旦屈服函数与塑性势不同、几何不再径向，或需保留一般 `dF/dsigma` 与 `dG/dsigma`，转 `cpa-implicit-return-mapping`。
- 主问题是 NPROPS/NSTATV、硬化对顺序、1/8/13 槽或 restart/SDV 映射时，转 `umat-props-statev-contract`。
- 已观测到失败迭代部分改写 `STRESS/STATEV/SPD` 时，与 `umat-transactional-state-update` 同时调用。
- 应力/状态映射已通过、只剩候选 `DDSDDE` 是否一致时，转 `ddsdde-finite-difference-audit`。
- 本 skill 内完成失败检测与 clean rollback；只在可恢复类局部失败需与宿主重试握手时，转 `umat-failure-cutback-protocol`。
- `q≈0` 的分支前域守卫属本 skill；只有要 clamp、加人工参数或改变物理域时，转 `constitutive-domain-stabilization-audit`。
- Hill48 标定/适用性转 `hill48-yield-calibration-applicability-audit`；不要用更换等效应力的方式复用本径向残差。

---

## E — 可执行步骤 (Execution)

1. **执行机制与运动学门**
   - 确认 Abaqus/Standard `UMAT`、三维小应变、`NDI=3`、`NSHR=3`、`NTENS=6`、关联 J2、各向同性线弹性和单一标量 `epbar`。
   - 确认屈服面中心不移动，不存在背应力、率项、损伤或非关联势。
   - **完成标准**：能唯一写出 `q=sqrt(3/2*s:s)`、`F=q-sigma_y(epbar)` 和 `Delta epbar=Delta gamma`的适用前提。
   - **判停条件**：任一前提不成立时，停止复用 `3G+H` 径向特例并路由到相邻 skill。

2. **建立具体实现的接口版本**
   - 逐下标列出 PROPS、STATEV、单位、初值、剪切表示、更新时机和表尾策略，不要从变量名猜测 ABI。
   - 使用下表只做已知版本识别，不把其合成新默认：

     | 版本 | 硬化契约 | STATEV 契约 |
     |---|---|---|
     | legacy 13 槽/UHARD | `(sigma_y,epbar)` | 6 弹性应变 + 6 塑性应变 + `epbar`；应变 Voigt 剪切为工程量 |
     | 8 槽 F90 | `(epbar,sigma_y)` | `epbar` + 6 塑性张量应变 + `Dp`；塑性剪切 SDV 为张量量 |
     | 1 槽 `umat3` | `sigma_y=50+200*epbar` | 仅 `STATEV(1)=epbar` |

   - 检查 `E>0`、`-1<nu<0.5`、数组长度、有限值、`epbar` 严格递增、`sigma_y>0` 且对本 skill 非递减；允许明示声明的表尾平台 `H=0`。
   - **完成标准**：材料卡、源码读取、`*DEPVAR` 和后处理对同一带版本契约给出相同解释。
   - **失败路径**：反序、奇数尾项、重复 `epbar`、NaN 或负硬化斜率按不可恢复输入/模型错误处理，不请求 cutback。

3. **保存 committed 快照并构造弹性试算**
   - 深拷贝应力、全部 STATEV、能量和诊断量，只在 trial 副本上计算。
   - 计算 `sigma_trial=sigma_n+Ce:Delta epsilon`、试静水压力 `p_trial`、试偏应力 `s_trial`、`q_trial` 和带符号 `F_trial`。
   - **完成标准**：`Ce`、`sigma_trial`、`q_trial`、当前 `sigma_y` 和 `F_trial` 均有限，且 committed 数组逐位未变。

4. **在归一化前执行带符号分支**
   - 使用 `tol_F=atol+rtol*max(sigma_ref,abs(q_trial),abs(sigma_y))` 之类的有量纲尺度，不要用无单位说明的裸常数。
   - 若 `F_trial<=tol_F`，接受弹性分支：保持 `epbar`/塑性历史，返回弹性切线，不计算流动方向。
   - 只当 `F_trial>tol_F` 且 `q_trial>tol_q` 时计算试偏应力方向。
   - **完成标准**：零增量和纯静水路径不执行任何零分母运算，且显著负 `F_trial` 不会因取绝对值进入塑性。
   - **失败路径**：`F_trial>tol_F` 却 `q_trial<=tol_q` 表明屈服/硬化契约非法；报域错误，不添加任意极小分母。

5. **用带括号的 Newton 求标量根**
   - 对非递减硬化，使用 `Delta gamma in [0,F_trial/(3G)]` 作物理括号，以 0 为初值并将 Newton 候选限制在括号内。
   - 每轮以 `epbar_n+Delta gamma` 重新查询同一活动区间的 `sigma_y,H`，计算 `R` 和 `-(3G+H)`。
   - 检查 `Delta gamma>=0`、候选 `epbar` 在已声明的表尾策略内、`3G+H` 远离零，且所有量有限。
   - **完成标准**：在有限迭代预算内同时通过尺度化残差、括号、有限性和物理域门，并记录最终 `R`、区间与迭代数。
   - **失败路径**：残差停滞/恶化、分母病态或超预算时，不使用最后一次候选值，转步骤 8。

6. **成套重建应力与历史**
   - 计算 `epbar_new=epbar_n+Delta gamma`、`q_new=q_trial-3G*Delta gamma` 和 `s_new=(q_new/q_trial)*s_trial`，保持试静水压力不变。
   - 以 `Delta epsilon_p=Delta gamma*(3*s_trial/(2*q_trial))` 更新张量塑性应变；在 Abaqus 应变向量边界显式转换工程剪切。
   - 按已声明的版本重建弹性应变、塑性应变、`epbar`、耗散和诊断量，不要跨版本套槽。
   - **完成标准**：`tr(s_new)=0`、压力未被塑性修正、`epbar_new>=epbar_n`，且重算 `q_new-sigma_y(epbar_new)` 在容差内。

7. **生成并标记候选切线/能量**
   - 弹性分支返回 `Ce`；塑性分支对实际径向更新和当前活动硬化斜率推导候选 Jacobian。
   - 在屈服切换和硬化表拐点标记活动集/左右斜率，不要声称存在唯一中心导数。
   - 按 Abaqus 接口契约显式赋值需要的能量和热力输出；不要用 SDV 中的 `Dp` 借证 `SPD` 已正确返回。
   - **完成标准**：所有输出已赋值且切线被诚实标记为“弹性/候选算法/近似”，未经 FD 前不写“已一致”。

8. **执行验收、原子提交或回滚**
   - 在提交前重查残差、有限性、物理域、状态单调性、能量符号和全部输出赋值。
   - 全部通过后一次写回 `STRESS/STATEV/能量/DDSDDE`；任一失败时恢复步骤 3 快照。
   - 把非法参数/布局标为不可恢复错误；只把有证据表明缩小增量可恢复的局部求解失败交给 cutback 协议。
   - **完成标准**：函数只能以“成功且成套提交”或“失败且完整回滚”返回，不存在 warning/静默耗尽后提交。

9. **执行专用回归与分层验收**
   - 先测零增量、纯静水、单轴、纯剪、多轴比例路径、卸载/再加载、表尾平台和硬化拐点。
   - 再用严格同参的单 C3D8/C3D8R 与内置 J2 对照 `S`、`PEEQ/SDV`、反力、能量和迭代数，并扫描增量尺寸。
   - 最后用 `ddsdde-finite-difference-audit` 对完整更新逐列分类中心、单边和不可微扰动。
   - **完成标准**：每层都有预期值、误差范数、容差和完整历史；不要用云图目测或 `JOB_COMPLETED` 代替数值验收。

---

## B — 边界 (Boundary)

### 不要在以下情况使用本 skill

- 不要用于平面应力/壳；它们需要额外的面外约束求解，不能直接使用固定六分量径向流程。
- 不要用于有限应变/有限转动、VUMAT、热/率相关塑性、随动/混合硬化、损伤、多面活动集或 J2 变形理论土模型。
- 不要用于 Hill48 或 non-AFR；更换 `q` 的名称不会保留试方向、`3G`、标量残差或切线。
- 不要把递减的 `sigma_y(epbar)` 当成本 skill 的单调硬化表；软化会改变根结构、局部化和对象性要求。

### 阻断以下失败模式

- 阻断在弹塑分支前无条件计算 `s/||s||`，也不要用极小常数静默改变该域。
- 阻断把 `(sigma_y,epbar)` 与 `(epbar,sigma_y)` 混装，或把 13/8/1 槽 STATEV 当作同一布局。
- 阻断冻结 Newton 初始硬化斜率；每个候选 `epbar` 都必须同步查值与斜率。
- 阻断无界 `DO WHILE`、无尺度绝对容差、无有限性/分母/域检查，或迭代耗尽后 warning/静默提交。
- 阻断在塑性返回后把弹性 `Ce` 命名为 consistent tangent；也不要用数值对称性或作业完成借证。
- 阻断把失败的最后 `Delta gamma`、部分应力、`epbar`、耗散或切线留给宿主重试。

## 相关 skills

- **depends-on**: 无——在三维小应变关联 J2 与标量各向同性硬化的前提已声明后，可独立构造径向返回。
- **contrasts-with**: `cpa-implicit-return-mapping`、`hill48-yield-calibration-applicability-audit`——本 skill 利用 J2 几何降为固定方向标量残差；一般 `F/G` 回映和 Hill48 标定分别由两者主责。
- **composes-with**: `umat-props-statev-contract`、`ddsdde-finite-difference-audit`——先锁定硬化表与 1/8/13 槽历史 ABI，再对完成的径向更新审计完整 Jacobian。

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
