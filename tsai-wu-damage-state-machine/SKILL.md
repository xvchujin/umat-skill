---
name: tsai-wu-damage-state-machine
description: |
  当 Tsai-Wu Phi/e 已触发，用户要设计或审计 argmax(Xphi) 归因、Instant/Recursive/dmg←dmg/e damage evolution、legacy 13-STATEV 的 dmg/fflags/delete 历史、KINC 跨步重置或 first/current/latest event 语义时调用。把“判据—归因—演化—删除”做成不可逆事务状态机；完整事件账本必须版本化扩容，不计算 Tsai-Wu 参数，也不把任一退化律当唯一结论。比较哪种 law 正确时必须组合 `softening-objectivity-audit`。
---

# Tsai-Wu 起始—归因—退化的不可逆状态机

## I — 方法论骨架 (Interpretation)

一个标量失效判据不能直接充当完整损伤模型。
第一层“起始”只回答 `e` 是否到达强度包络；第二层“归因”决定哪个方向或模式被激活；第三层“演化”决定刚度怎样随历史变化。
某些实现用 `argmax(φ1…φ6)` 连接前两层，这只是方向归因启发式，交互贡献接近时必须允许并列或不确定。
直接、递归和 `1/e` 折减是三种不同演化语义，不是同一公式换个系数。
状态应至少分成当前剩余刚度 `dmg` 与首次触发时序 `fflags` 两本账，且 trial 失败不能污染 committed 历史。
参数名必须明确表示“削去比例”还是“剩余比例”，否则 `0.9` 与 `0.1` 会产生相反含义。
状态机完成后仍需增量、网格、能量和切线审计，不能用 SDV 云图代替验证。
源码已证明 13 槽布局：`STATEV(1:6)` 是 11/22/33/12/13/23 的剩余刚度乘子，`STATEV(7:12)` 是会覆盖的带符号 `KINC`，`STATEV(13)` 是删除状态。
该 legacy 13 槽只能表达“当前 `dmg` + 会覆盖的 latest `±KINC` + delete”，容不下独立初始化标志和 first/current/latest 三套事件账本；修复版必须声明新的布局版本并增加 `NSTATV`，不能静默改变原槽义。
`KINC==1` 不是首次材料调用；把它当初始化条件会在每个新 step 恢复损伤和删除状态。

---

## A2 — 触发场景 (Future Trigger)

### 用户会在什么情境下需要这个 skill?

1. Tsai-Wu `e≥1` 后不知道如何选择损伤方向或更新刚度。
2. 需要在 `STATEV/SDV` 中同时保存六方向损伤和首次触发顺序。
3. 在直接折减、递归折减和 `1/e` 折减之间选择或重构演化器，并用软化客观性证据比较而非凭一次曲线定胜负。
4. `beta=0.9/0.1`、`dmg=0/1` 的参数含义或更新方向容易写反。
5. 多步分析中损伤在新 step 首增量恢复，或 `fflags` 被后续增量覆盖。

### 语言信号 (用户的话里出现这些就应激活)

- “Tsai-Wu 失效后折减哪个方向 / damage direction”
- “φ1 到 φ6 最大项怎么用 / argmax contribution”
- “InstantDamage 和 RecursiveDamage 有什么区别”
- “dmg、fflags、SDV1–12 怎么映射”
- “KINC=1 为什么把损伤清零 / multistep history reset”
- “fflags 是 first event 还是 latest event”

### 与相邻 skill 的区分

- 与 `tsai-wu-parameter-audit` 的区别：前者把材料应力算成可靠的 `e`；本 skill 从已触发的 `e` 开始组织方向、演化和历史。
- 与 `softening-objectivity-audit` 的区别：本 skill 定义候选状态机；用户比较哪种退化律“正确”时必须把候选交给后者做增量、网格和能量检验，未过门不得定论。
- 与 `umat-transactional-state-update` 的区别：后者规定所有 UMAT 的 trial/commit 事务；本 skill规定 Tsai-Wu 特有的两本损伤账。
- 与 `cpa-implicit-return-mapping` 的区别：本 skill 由非塑性失效指数 `e` 触发方向归因与退化；CPA 用塑性乘子 `Δλ` 满足屈服一致性，两者不能共享残差或回映方程。
- 与 `ddsdde-finite-difference-audit` 的分工：本 skill 生成已接受的损伤状态与退化响应；后者以完整更新为黑箱审计阈值两侧及冻结活动集下的 Jacobian。

---

## E — 可执行步骤 (Execution)

1. **锁定起始层输入**
   - 只接收已通过参数/坐标审计、且六槽已全量初始化并有限的 `e`、材料应力和 committed 损伤状态。
   - 判停条件：若 `e` 的单位、材料轴或触发不等式未通过测试，返回 `tsai-wu-parameter-audit`，不得进入退化。
   - 完成标准：`e<1` 与 `e≥1` 分支在阈值两侧可复现。

2. **显式声明归因规则**
- 计算 `φ1…φ6`，记录最大值、次大值和间隔；把 `argmax` 标为实现相关启发式。
   - 完成标准：并列容差、交互项显著或模式不可辨时，不会因浮点噪声任意跳向；系统能输出“不确定/多方向”状态或调用独立模式准则。

3. **选择并写清演化语义**
   - 在一次残余刚度、按物理演化量连续退化或其他已标定律中选一条；写清 `beta` 是削去还是保留、残余下限、继续触发条件及不可逆约束。
- 对每种候选更新式逐一命名实际语义：Instant=`0.99999999-beta`，Recursive=逐调用递乘，Const=每次满足条件时执行 `dmg_i←dmg_i/e_i` 且 beta 为死输入；它不是 `1-e`，也不是把 `dmg_i` 一次性赋成 `1/e_i`。
   - 完成标准：用手算两步即可验证更新方向、上下界和重复调用结果；源码名称、注释、参数读写与公式一致。

4. **维护 trial/committed 双账本**
   - 先选择并写入布局版本。`legacy-13` 只保留 `1:6=dmg`、`7:12=latest ±KINC`、`13=delete`，不得声称拥有 first/current 或可靠的一次性初始化语义。
   - 若需要完整事件账本，采用显式扩容版本，例如 `event-ledger-v2`：保留 legacy `1:13`，追加 `14=initialized`、`15:20=first-event total time`、`21:26=current-active`、`27:32=latest-event total time`，因此要求 `NSTATV>=32`；确切版本必须同时写入材料卡、restart 与后处理契约。
   - `dmg_i` 保存当前剩余刚度乘子；first/current/latest 各有唯一槽义，失败试算全部回滚。使用一次性初始化标识，不用 `KINC==1` 推断首次调用；把删除状态也纳入同一事务。
   - 完成标准：入口长度守卫拒绝把 v2 写进 13 槽；新 step、cutback、重复调用和 restart 不会恢复损伤；首次事件不被覆盖；拒步前后 committed 状态逐槽一致。

5. **映射到刚度、SDV 和诊断**
   - 用显式的材料方向—刚度分量—状态槽位表更新退化矩阵，并输出触发原因、方向和历史。
   - 完成标准：六个单方向试验命中预期 SDV 和刚度分量；3 向压缩只由 `STRESS(3)` 分类；`*DEPVAR, DELETE=13` 与删除状态契约一致。

6. **移交客观性与切线审计**
   - 对状态机运行增量/网格/能量测试，并对完整应变→损伤→应力映射扰动。
   - 完成标准：未通过 `softening-objectivity-audit` 和 `ddsdde-finite-difference-audit` 前，不宣称模型已验证。

---

## B — 边界 (Boundary)

### 不要在以下情况使用此 skill

- 仅需要计算 Tsai-Wu 系数或失效指数：使用参数审计 skill。
- 需要已验证的纤维/基体、拉伸/压缩模式准则：`argmax(φ_i)` 不足以替代专用模式模型。
- 想把损伤过程改写为塑性返回映射：该状态机没有塑性乘子 `Δλ`。

## 相关 skills

- **depends-on**: `tsai-wu-parameter-audit`——只有材料轴、强度、交互项和失效指数 `e` 通过前置审计，才能进入方向归因与退化。
- **contrasts-with**: 无——塑性与损伤可以在声明耦合顺序后共存，不强造二选一关系。
- **composes-with**: `ddsdde-finite-difference-audit`——对退化后的完整离散映射审计返回 Jacobian。

---

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
