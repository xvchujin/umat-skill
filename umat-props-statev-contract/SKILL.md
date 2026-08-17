---
name: umat-props-statev-contract
description: |
  当用户定义、审计或迁移 User Material 的位置 ABI，出现“NPROPS/NSTATV/Depvar mismatch / PROPS order / STATEV-SDV mapping / restart migration”，尤其涉及 J2 的 13/8/1 槽、相反硬化点顺序或 Tsai-Wu 的精确 23 PROPS/13 STATEV 时调用。先盘点实际读写，再输出版本化逐槽契约、长度/取值守卫和迁移证明；任一目标历史不能唯一重建即拒绝直接 restart。积分器、Voigt 数学映射和损伤演化不由本 skill 决定。
---

# PROPS、STATEV 与 SDV 的可审计位置契约

## I — 方法论骨架（Interpretation）

1. 把 `PROPS`、`STATEV` 和 `SDV` 当作版本化位置 ABI；不要给数字下标假定跨实现通用的物理名称。
2. 从实际源码读写、材料卡/Depvar 和 ODB 后处理三方建立契约；不要只抄注释、变量名或屏幕数量。
3. 为每个 `PROPS(i)` 固定名称、单位、符号、合法域、来源、顺序和只读语义；把硬化点的二元组顺序写成布局的一部分。
4. 为每个 `STATEV(i)` 固定初值、物理类型、剪切表示、演化方向、不可逆性、trial/commit 时机、旋转规则和 `SDVn` 名称。
5. 在任何数组访问前校验 `NPROPS/NSTATV`、奇偶/点数、有限性、排序和布局版本；不要依赖整数截断或“用户应该填对”。
6. 把连续幅值、事件时序和删除状态分槽；先定义 `first/current/latest` 语义，再解释 `fflags`，不要因名称把覆盖式记录当首次事件。
7. 把相同物理模型的 13/8/1 槽实现视为三个 ABI；把相同 13 槽数量的 J2 与 Tsai-Wu 视为完全不同 ABI。
8. 迁移 restart 时逐槽证明可逆性；若目标槽缺少唯一来源、单位/剪切语义不明或历史不可从当前快照重建，拒绝直接迁移并要求重新初始化/重算或用户批准的显式策略。
9. 每次扩展先更新契约、材料卡、Depvar、输出脚本与迁移版本，再改算法；不要事后猜 SDV 含义。

### 证据化 ABI 样板：只绑定下列已审计实现

#### J2 三套 STATEV 与两种硬化表顺序

| 布局版本 | PROPS/硬化数据 | STATEV 精确布局 | 关键边界 |
|---|---|---|---|
| legacy/UHARD 13 槽 | `PROPS(1:2)=E,nu`；从 3 起为相邻 `(sigma_y,epbar)` | `1:6=εe`，`7:12=εp`，`13=epbar`；应变历史按 Abaqus 工程剪切 | 3D 时 `NSTATV>=13`；张量历史需按 `DROT/ROTSIG` 规则处理 |
| 新 F90 8 槽 | `PROPS(1:2)=E,nu`；从 3 起为相邻 `(epbar,sigma_y)` | `1=epbar`，`2:7=εp(11,22,33,12,13,23)`，`8=Dp`；剪切为张量剪切 | `NSTATV>=8`；`(NPROPS-2)` 必须为正偶数；该源码未旋转历史 |
| `umat3.for` 1 槽 | `PROPS(1:2)=E,nu`；`sigma_y=50+200*epbar` 硬编码 | `1=epbar` | `NSTATV>=1`；不存在可迁移的张量应变或耗散历史 |

#### Tsai-Wu 准代码的精确 23/13 契约

| PROPS | 名称与语义 |
|---|---|
| `1:3` | `E11,E22,E33`，材料轴正模量 |
| `4:6` | `nu12,nu13,nu23`，工程泊松比 |
| `7:9` | `G12,G13,G23`，正剪切模量 |
| `10:15` | `Xt,Xc,Yt,Yc,Zt,Zc`，拉/压强度均用正幅值 |
| `16:18` | `S12,S13,S23`，正剪切强度 |
| `19:23` | `beta_ft,beta_fc,beta_mt,beta_mc,beta_s`；`ConstDamage` 读入/传递但其 `1/e` 演化不使用这五项 |

| STATEV | 代码事实 | 不得误读 |
|---|---|---|
| `1:6` | `dmg(11,22,33,12,13,23)`，初值 1 的剩余刚度乘子 | 不是从 0 增至 1 的通用损伤变量 |
| `7:12` | `fflags(1:6)`，实数槽中的带符号 `KINC`，后续触发会覆盖 | 不是可靠的首次事件记录，也不是 Boolean |
| `13` | `Del_Stat`：1 活动、0 请求删除 | 还必须由 deck 明确接成删除变量 |

上表是源码已经证明的 `legacy-13`，只能表示当前 `dmg`、会覆盖的 latest `±KINC` 与删除状态。若需求同时包含可靠的一次性初始化及 first/current/latest 三套事件语义，13 槽在容量和语义上都不足；必须建立新的 ABI，不能只改变量名。

一个可审计的扩容例是 `event-ledger-v2`：保留 `STATEV(1:13)` 以便识别 legacy 输出，追加 `14=initialized`、`15:20=first-event total time`、`21:26=current-active`、`27:32=latest-event total time`，因此入口要求 `NSTATV>=32`。该 v2 是针对旧实现缺陷的版本化修复契约，不是旧布局的既有事实；材料卡、`*DEPVAR, DELETE=13`、restart 和后处理必须共同声明 v2，旧 13 槽 restart 也不能凭空恢复缺失的 first/current 历史。

---

## A2 — 触发场景（Future Trigger）★

### 用户会在什么情境下需要这个 skill？

1. 给现有 UMAT 增加材料常数、硬化变量、损伤方向或首次事件标志。
2. CAE 的 Constants/Depvar 数量与代码最大下标不一致，或开启 bounds check 后越界。
3. SDV 云图能显示，但无法确定某个 SDV 是累计损伤、剩余刚度还是事件时序。
4. 两套 UMAT 都使用 `STATEV(1)`，却分别代表 `edp` 与 `dmg(1)`，迁移时发生语义污染。
5. 审查材料卡单位、参数来源、初始化和不可逆提交规则。
6. 把 J2 13 槽 restart 改为 8 槽、交换硬化表列，或把同为 13 槽的 J2 状态误装到 Tsai-Wu。

### 语言信号（用户的话里出现这些就应激活）

- “PROPS 的顺序怎么定义？”
- “NPROPS/NSTATV 或 Depvar mismatch。”
- “STATEV/SDV mapping 对不上。”
- “What does SDV7 mean?”
- “加一个历史变量会不会把旧结果读错位？”
- “Can I restart a 13-state J2 job with the 8-state UMAT?”
- “sigma_y,epbar or epbar,sigma_y?”
- “Tsai-Wu exact 23 PROPS / 13 STATEV contract.”

### 与相邻 skill 的区分

- 与 I01“机制路由”的区别：I01 选择更新器；本 skill 规定选定模型的参数与历史量放在哪些槽位。
- 与 `umat-transactional-state-update` 的区别：本 skill 定义 `STATEV(n)` 的语义；事务更新决定 trial 何时可提交到这些槽位。
- 与 `abaqus-tensor-voigt-adapter` 的区别：本 skill 处理材料参数和历史数组的位置协议，不处理应力/应变分量顺序与剪切因子。
- 与 `tsai-wu-damage-state-machine` 的区别：本 skill 记录 `dmg/fflags` 的槽位、方向和时序；损伤状态机决定触发、归因和演化规则。
- 与 `j2-isotropic-hardening-radial-return` 的区别：本 skill 固定硬化对顺序、1/8/13 槽语义和迁移门；后者在该 ABI 上执行径向返回，不得用积分器猜测或静默改写槽义。
- 与 `umat-failure-cutback-protocol` 的区别：本 skill 证明 NPROPS/NSTATV 或材料卡契约为何无效；后者执行不可恢复失败出口、完整回滚和宿主认可的明确终止，不能用 PNEWDT 修复配置。

---

## E — 可执行步骤（Execution）

当 skill 被激活后，agent 应按以下步骤执行：

1. **从实际实现盘点所有位置访问**
   - 收集代码中的每个 `PROPS(i)`、`STATEV(i)` 读写，以及材料卡 Constants、Depvar、删除槽和请求输出的 SDV；给每项记录源码 SHA/布局版本。
   - 完成标准：得到最大访问下标、逐处读写和证据等级；屏幕、OCR、注释与完整源码分别标注。
   - 判停条件：若只有数量而没有可信逐槽证据，标记契约不完整，不补猜缺失项。

2. **建立 PROPS 位置契约表**
   - 每行至少含：布局版本、下标、变量名、物理意义、单位、符号、合法范围、材料卡来源和代码读取位置；把相邻点对顺序、点数、排序与表尾策略写入表头。
   - 完成标准：User Material 的每一项恰好映射一个表项；J2 两种相反点对顺序可被机器式逐对解释，Tsai-Wu 23 项无重复、空洞或未声明死输入。
   - 判停条件：单位或拉/压强度符号不明时，停止数值填卡并请求标定来源。

3. **建立 STATEV/SDV 历史语义表**
   - 每行至少含：布局版本、下标、名称、标量/张量、单位、剪切表示、初值、演化方向、是否不可逆、读入阶段、trial 更新、提交/回滚、旋转规则和 SDV 名。
   - 完成标准：J2 13/8/1、Tsai-Wu `legacy-13` 与所选扩容版本分别成表；若采用完整事件账本，入口明确守卫 `event-ledger-v2` 的 `NSTATV>=32`。每个状态量都能回答“从哪里来、何时改、失败时怎么办、下一增量怎样读”。

4. **分离幅值、事件和状态方向**
   - 当前塑性/损伤幅值、首次/最近事件和删除/存活状态分别使用独立槽位；明确 `dmg` 是剩余刚度乘子还是累计损伤变量，并从代码验证 `fflags` 的 first/current/latest 语义。
   - 完成标准：不可逆字段不会因新 step 或拒绝 trial 被重置；若现有实现会覆盖 flags，契约如实写“latest”而不美化成“first”；需要 first/current/latest 时扩容并版本化，绝不把它们硬塞回 13 槽。

5. **加入入口长度与取值守卫**
   - 检查 `NPROPS`、`NSTATV` 至少覆盖最大访问下标，并检查必要参数有限、单位一致、模量/强度/乘子范围合理。
   - 完成标准：配置不足时在第一次越界访问前产生可诊断的受控失败，并保持 committed 状态。
   - 判停条件：不得依赖“使用者应该配置正确”继续执行；确认是永久配置错误后，转交 `umat-failure-cutback-protocol` 的不可恢复分支，保持 committed 并明确终止，不得循环 `PNEWDT`。

6. **证明迁移或明确拒绝**
   - 为旧→新逐槽列出 `copy/scale/derive/initialize/drop/reject`，包括单位、工程↔张量剪切、不可逆历史和目标槽来源；不要因数组长度相同或物理模型同名直接复制。
   - 对 13→8 J2 明确处理：`epbar` 可候选映射，塑性剪切需因子转换，但目标 `Dp` 在旧快照中通常无唯一来源；对 8→13 明确目标弹性应变历史是否可由受控小应变快照唯一重建。任一证明缺失即拒绝直接 restart。
   - 完成标准：每个目标槽都有唯一、可测试且有误差/守恒断言的来源；否则输出“迁移拒绝 + 缺失信息 + 可接受的重新初始化/重放方案”，不生成静默默认值。

7. **三方对账并冻结版本**
   - 对照代码表、CAE 材料卡/Depvar、restart/初始条件和 ODB 的 SDV 解释；给契约加实现版本或源码哈希，布局变化时提升版本。
   - 完成标准：抽取至少一个 PROPS、一个连续 STATEV、一个事件/删除 STATEV 做三方对账；再用错版本材料卡与 restart 做预期拒绝测试。

---

## B — 边界（Boundary）★

### 不要在以下情况使用此 skill

- 只需要选择显式、隐式或 Tsai-Wu 更新器时；使用 I01。
- 只需要修复候选态/提交态污染而槽位语义已经清楚时；使用 I02。
- 只需要解决 2D/3D、工程剪应变或材料坐标变换时；使用 I04。

## 相关 skills

- **depends-on**: 无——槽位、单位、初始化和历史语义是其他更新技能的接口前提。
- **contrasts-with**: 无——槽位契约与张量表示是共同前置，不是二选一方案。
- **composes-with**: `abaqus-tensor-voigt-adapter`、`j2-isotropic-hardening-radial-return`、`umat-failure-cutback-protocol`——本 skill 固定参数/历史槽位，分别与张量适配、J2 径向更新组成完整接口；若守卫发现永久配置错误，失败协议负责保持 committed 并明确终止。

---

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
