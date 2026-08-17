---
name: umat-failure-cutback-protocol
description: |
  当 UMAT 局部预算耗尽，出现 infinite loop、warning-after-submit、silent exhaustion，或要设计 clean rollback、failure code、PNEWDT/cutback handshake 时调用。区分 J2 不返回、污染返回、假成功与 NPROPS/NSTATV 等配置错误；仅合法输入下可由缩步恢复的失败请求 cutback。日常 local DT/漂移修正不用；原子回滚由 `umat-transactional-state-update` 主责，槽位错误由 `umat-props-statev-contract` 定位。
---

# UMAT 局部失败到全局 Cutback 的升级协议

## I — 方法论骨架 (Interpretation)

材料点失败应按层级处理：先在 UMAT 内做有界、可回滚的局部恢复；只有输入合法、局部预算耗尽且缩步可能改变轨迹时，才请求宿主缩小全局增量。
任何试算前都要有完整 committed 快照；失败出口必须返回旧状态，而不是部分更新状态或最后一次坏 trial。
失败不仅是一个数值标志，还应携带阶段、原因、材料点位置、残差、最小局部步长和重试次数等诊断。
局部 `DT` 的缩小只重算当前材料点内部路径；`PNEWDT` 是向 Abaqus 请求改变全局增量的接口，两者不能混为一个控制器。
设置 `PNEWDT<1` 只是协议的一半：还必须按目标 Abaqus 版本满足所有必需输出契约，并在求解日志中验证宿主确实放弃并重算了当前增量。
若 `PNEWDT` 被注释、覆盖、未初始化或宿主设置不采纳，恢复旧状态可能表现成假成功、零刚度/零更新或更晚的异常。
不同失败阶段可采用不同建议比例，但 `0.75/0.5/0.25` 只能作为示例策略，必须配置化并用重试成本与稳定性验证。
无法建立干净回滚或确认宿主握手时，应停止并暴露错误，不能让分析带着不一致状态继续。
先按宿主可观察行为把失败分成三类：无限循环/NaN 比较造成**不返回**；warning 后写回应力和历史造成**污染返回**；静默耗尽或只退旧态但不发有效握手造成**假成功**。
再单列永久配置错误：短 `PROPS/STATEV`、不支持的 `NTENS`、非法材料参数、损坏源码和缺失外部依赖不随 `DTIME` 改变，禁止循环 cutback。
只把“输入合法且更小全局增量可能改变局部轨迹”的失败标成 recoverable；其余失败保持 committed 并走可解释终止。

---

## A2 — 触发场景 (Future Trigger)

### 用户会在什么情境下需要这个 skill?

1. α 求根、局部子步、漂移修正或材料域检查达到迭代/重试上限。
2. UMAT 写了 `PNEWDT`，但 Abaqus 没有明显减小增量或重算，作业却继续产生异常状态。
3. 失败分支恢复了旧 `STRESS/STATEV`，但能量、Jacobian、诊断或其他输出不确定。
4. 代码注释声称会 cutback，实际赋值被注释、覆盖或只存在于不可达分支。
5. 需要设计 clean failure、global retry、cutback handshake 或 failure escalation policy。
6. `NPROPS/NSTATV` 不足、材料参数非法或运动学不支持，需要决定为何不能继续 cutback、怎样保持 committed 并明确终止。
7. J2 局部循环出现三种表象：调用卡住不返回、warning 后照常写回、次数耗尽却没有 failure 标志。
8. 反复减小全局增量仍在同一个数组读取、非法参数或缺失依赖处失败。

### 语言信号 (用户的话里出现这些就应激活)

- “PNEWDT 不生效 / Abaqus ignores cutback”
- “局部积分失败后怎么安全返回 / clean rollback”
- “substep retries exhausted / root solver max iterations”
- “状态回到旧值但计算还继续 / silent zero update”
- “0.75、0.5、0.25 应该怎么选 / cutback policy”
- “这个错误与步长无关，怎样停止而不是无限 cutback？”
- “infinite local loop / warning then commit / silent Newton exhaustion”
- “每次都在 PROPS(15) 或 NTENS 检查处失败，还要继续 cutback 吗？”

### 与相邻 skill 的区分

- 与 `explicit-alpha-yield-intersection`：后者负责构造括区并求 `α`；本 skill 只接管其无根、停滞或预算耗尽的失败出口。
- 与 `explicit-adaptive-substepping`：后者优先调整 UMAT 内部局部 `DT`；本 skill 在局部恢复无效时请求 Abaqus 缩小全局增量。
- 与 `explicit-yield-drift-correction`：后者尝试有界局部修复；本 skill 确保修复失败不会提交坏状态。
- 与 `umat-transactional-state-update`：后者保证失败返回前完整恢复 committed 输出；本 skill 在此基础上分类失败并与宿主完成 cutback/终止握手。
- 与 `constitutive-domain-stabilization-audit`：本 skill 处理“当前增量太大、可通过重试恢复”的数值失败；若公式落入物理不可容许域或拟用稳定化改模，先做模型域审计。
- 与 `umat-props-statev-contract`：后者发现并解释槽位契约错误；本 skill 接管其失败出口，把该错误标为不可恢复、保持 committed，并使用目标环境认可的诊断/终止机制，绝不循环 cutback。

---

## E — 可执行步骤 (Execution)

1. **建立失败分类和升级策略表**
   - 先按宿主行为建立四个顶层码：`NONRETURN_RISK`（无限循环/NaN 判停）、`CONTAMINATED_RETURN`（warning 后提交）、`FALSE_SUCCESS`（静默耗尽/旧态无握手）和 `CONFIGURATION_ERROR`（数组、参数、运动学、源码或依赖永久错误）。
   - 再细分交点无括区/求根停滞、局部误差超限、局部步长下限、漂移停滞、非有限状态与物理域违规；为每类指定可否局部恢复、最大次数、回滚层级、建议 `PNEWDT`、诊断字段和最终停止条件。
   - 完成标准：每个失败码只有一个首因和一个宿主动作；三类 J2 失败与配置错误各至少有一个故障注入，且不存在“失败但按成功提交”的出口。

2. **定义并测试 committed 快照边界**
   - 在本次全局增量开始及每个可提交子步处，保存应力、全部 `STATEV`、能量/耗散、局部路径、切线缓存和其他会被 trial 改写的量。
   - 完成标准：向每个失败点注入故障后，返回数组与选定 committed 状态逐分量一致，trial 不留下净影响。
   - 判停路径：若无法确认哪些输出已被污染，禁止继续分析，先修复状态所有权。

3. **先耗用有界局部恢复预算**
   - 只对合法输入下可能随路径分辨率改善的求根、误差或漂移失败耗用预算；求根失败可重建括区，误差失败可缩局部 `DT`，漂移失败可回滚换方向。
   - 在进入任何迭代前检查数组长度、运动学、材料域和外部依赖；配置错误直接跳到步骤 8，不消费一次局部或全局 cutback。
   - 完成标准：局部尝试严格减少某个明确控制量，且有次数/步长下限；重复相同状态不会形成死循环。
   - 判停路径：预算耗尽、无有限候选、物理域不可恢复或控制量不再改善时，立刻升级，不再追加隐藏重试。

4. **在失败出口做原子回滚**
   - 恢复全局增量进入 UMAT 时应保持的 `STRESS/STATEV` 及其他宿主会读取的输出；将坏 trial 只保留在诊断副本。
   - 完成标准：返回给宿主的状态自洽、有限且不混合新旧分量；失败原因和建议比例在回滚后仍可观测。

5. **发出有效的全局 cutback 请求**
   - 仅对标为 recoverable 的失败，在活动可执行语句中设置配置化的 `0<PNEWDT<1`，避免之后被覆盖；按目标 Abaqus 版本核对自动增量、接口和必需输出要求。
   - 完成标准：源代码检查能证明赋值可达且未注释；单材料点故障测试中日志显示当前增量被放弃，并以更小全局增量重新调用 UMAT。
   - 判停路径：目标过程不支持/不采纳该握手，或无法验证实际重试时，停止并报告接口不成立，不能把旧状态返回当作成功。

6. **保证失败返回的输出契约**
   - 明确 `DDSDDE`、能量项、热耦合项和状态输出在 cutback 返回时应保持旧值、给出安全值还是由宿主忽略；不要留下未初始化内存。
   - 完成标准：开启运行时未初始化/NaN 检查后，故障注入路径无未定义输出，且宿主可稳定完成重试。

7. **验证分层策略而非只验证常数**
   - 分别注入 α 求根、子步、漂移以及 J2 不返回/污染返回/假成功失败，检查各自的局部次数、回滚状态、`PNEWDT` 值和全局重试行为；再测试连续多次 cutback。
   - 完成标准：每个 recoverable 失败均能从日志重建“局部尝试 → 回滚 → 请求 → 宿主重试”；三类旧 J2 反模式都被新的有限失败出口截获，成功重试后没有双重累计历史。

8. **设置不可恢复的最终停止路径**
   - 对非法材料参数、数组尺寸不足、运动学不支持、损坏源码/缺失依赖、持续 NaN、全局增量降至工程下限或连续 cutback 上限，使用目标环境认可的终止/诊断机制。
   - 对配置错误证明“重试输入不会变化”：记录 offending index/value、所需契约与实际契约，不设置 recoverable `PNEWDT`。
   - 完成标准：最终停止包含材料点、步/增量、失败码和关键残差或契约差异；不会无限 cutback，也不会用裸 `STOP` 造成不可解释的并行行为。

---

## B — 边界 (Boundary)

### 五个控制量必须隔离

- `α`：弹性试探路径到首次屈服点的比例；其求解失败可触发协议，但 `PNEWDT` 不能充当一个替代 `α`。
- 局部 `DT`：UMAT 内部归一化路径的子步大小；局部重试只重算材料点路径，不直接改变 Abaqus 全局 `DTIME`。
- `Δλ`：塑性一致性/流动乘子；它的求解失败是一个失败原因，不是 cutback 比例。
- `PNEWDT`：UMAT 对下一全局时间增量相对当前增量的建议量；是否导致放弃/重试应以目标 Abaqus 过程和版本手册及实测为准。
- `η_emb`：嵌入积分的局部误差代理；它决定是否接受局部候选，但不是宿主失败码，也不能直接等同 `PNEWDT`。`η_emb` 与 Tsai-Wu 失效指数 `e` 必须使用不同变量名。

### 不要在以下情况使用此 skill

- 仍可通过少量局部缩步稳定恢复：先完成局部自适应，不要过早放大全局重算成本。
- 材料参数、数组维度、应力分量或运动学根本不受支持：不得进入可恢复 cutback 分支；必须走本 skill 的不可恢复终止路径并要求修正模型。
- 源码缺行/文本污染、外部库缺失或 `NPROPS/NSTATV` 永久不足时，缩步不会改变失败输入；重复 cutback 只会掩盖第一原因。
- 全局问题来自接触、边界条件、单元畸变或方程尺度，而材料点更新稳定：`PNEWDT` 不是通用全局收敛修复器。
- 试图用返回旧状态让作业“先跑完”：没有宿主重试的旧状态返回属于静默数据损坏风险。

## 相关 skills

- **depends-on**: `umat-transactional-state-update`——发出失败请求前必须原子恢复宿主会读取的完整状态。
- **contrasts-with**: `constitutive-domain-stabilization-audit`——可由较小全局增量恢复时选本 skill；物理域错误、奇异结构或稳定化改模时选后者。
- **composes-with**: `explicit-yield-drift-correction`、`umat-props-statev-contract`——有界漂移修正失败后，由本 skill 负责干净回滚和宿主握手；入口数组守卫发现不可由缩步恢复的永久配置错误时，两者共同保持 committed 状态并走明确终止路径。

---

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
