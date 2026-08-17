---
name: umat-semantic-debugging
description: |
  当继承/OCR/文档抽取的 UMAT/VUMAT Fortran 需要 source integrity、fixed/free form、array bounds、host I/O 或 dependency preflight，或代码能编译却出现“STRESS/STRESST、F/dF/dG wrong argument、DDSDDE/stateNew unassigned、silent Fortran bug、breakpoint trace”时调用。先做静态宿主数据流门，再用最小复现定位首个语义偏差。CPA 方程问题先用 CPA；仅复杂边值异常时先分层隔离。
---

# UMAT 候选态—提交态—返回量的语义调试

## I — 方法论骨架 (Interpretation)

1. 先证明手中的文本确实是可审计源码：记录来源、SHA、抽取/OCR 路径、编码、许可和缺失成员；不要把 Word 文档片段、OBJ 或文件名当成源码身份。
2. 再冻结构建语义：判断 fixed/free form、续行/列宽、编译器指令、include、目标 Abaqus/编译器 ABI 和外部库；不要让 `.for/.f90` 后缀代替格式证据。
3. 在执行前建立宿主数据流表：接口签名、`NDI/NSHR/NTENS`、最高数组下标、输入只读性、所有分支的输出完备性、初始化、退出路径和外部依赖。
4. 把 `IMPLICIT NONE`、显式接口、边界/未初始化检查视为揭示语义错误的门；不要把隐式类型“恰好编译”当作兼容。
5. 只有静态门通过后，才把模型缩成单积分点/单单元、少增量和确定路径；不要运行来源污染或契约阻断的旧代码来“看看会怎样”。
6. 把运行态分成 committed、predictor、局部第 `k` 个 iterate、收敛 candidate 和宿主输出；为对象、形状/单位、读写方向、坐标/Voigt 与状态层级建账。
7. 在入口、试算、分支、迭代、提交和返回检查不变量；定位第一条偏离预期的赋值/调用，不要在后续 NaN、云图或 Job 中止处猜原因。
8. 做最小修复后重放预期失败与正常邻近路径，清理阻塞式调试钩子，再交给分层验证恢复证据链。

### 静态预检必须回答的问题

| 门 | 必须产出 | 典型阻断证据 |
|---|---|---|
| 来源身份 | 原始/抽取路径、SHA、编码、完整性、许可、证据等级 | `CFULL(I,Symmetric model generationJ)` 证明文档字符串插入；隔离而非猜修 |
| 源格式 | fixed/free form、续行规则、有效列、行长、编译器指令、include | `.for` 依赖 `!DIR$ FREEFORM`；F90 行超常用 132 列；格式选错会截断或改义 |
| 接口/数组 | 目标版本签名、`NDI/NSHR/NTENS`、`NPROPS/NSTATV`、局部数组形状 | 六分量核心从四分量缓冲越界；注释长度小于实际最高下标 |
| 宿主读写 | 输入/输出分类、每条返回路径的赋值集合、old→new 复制 | 改写 `STRAN/charLength`；VUMAT 漏写 `stateNew` 或能量输出 |
| 初始化/退出 | 局部数组全赋值、NaN/域门、错误分类、事务退出 | `e(1:6)` 只写一槽却 `maxval`；深层 `XIT/xplb_exit` |
| 依赖/ABI | include、外部符号、库版本、许可、返回状态 | 旧 NAG `F01AAF` 缺库/已撤销且 `IFAIL` 未检查；旧签名未验证 |

---

## A2 — 触发场景 (Future Trigger)

### 用户会在什么情境下需要这个 skill?

1. UMAT 能编译甚至 Job 能推进，但应力、历史量或 `DDSDDE` 在某个增量开始失真。
2. 修改一个近名变量后结果巨变，怀疑 `F/dF/dG`、`STRESS/STRESST` 或 `De/DDSDDE` 接错。
3. `KINC≥某值` 才出错、拒步后历史污染，或返回前某数组仍为零/旧值。
4. 日志庞大、并行积分点太多，无法看清第一个异常调用。
5. 需要把编译错误、接口错误、状态层级错误和数值奇异分别定位。
6. 分层最小复现已经证明 UMAT 数据流先于接触/边界响应偏离，需要沿变量语义账本继续定位。
7. 收到旧 `.for`、OCR 或 Word 粘贴代码，不确定 fixed/free form、编码、续行或文本是否被污染。
8. 链接报 unresolved external、依赖旧 `F01AAF`/`aba_param.inc`，或怀疑源码修改了 `STRAN/charLength` 等宿主输入。
9. VUMAT 的 `stressNew/stateNew/enerInternNew/enerInelasNew` 只在部分分支赋值，或六分量局部数组通过任意 `NTENS` 接口调用。

### 语言信号 (用户的话里出现这些就应激活)

- “代码能跑但结果不对 / compiles but wrong result”
- “STRESS 和 STRESST 到底该传哪个？”
- “把 F 写成 dF 为什么不报错？”
- “DDSDDE 到返回时还是 zero”
- “STATEV 是这一轮还是上一步的值？”
- “怎么做 single-element breakpoint/data-flow debugging?”
- “最小单元已证明 UMAT 先出错，怎么追第一个错接？”
- “Is this fixed-form or free-form Fortran?”
- “OCR/source file may be corrupted / source integrity check.”
- “array bounds / writes to read-only host input / output not assigned.”
- “unresolved external F01AAF / missing library or include.”

### 与相邻 skill 的区分

- 与 `cpa-implicit-return-mapping` 的区别：CPA skill 给出带符号弹塑分支、`Δλ` 和局部判停协议；本 skill 只在该协议已明确后沿代码追踪实际变量是否履行它，不能用通用“语义错误”抢走算法定义问题。
- 与 `ddsdde-finite-difference-audit` 的区别：后者量化返回导数误差；本 skill 在误差出现后定位漏赋、旧状态或错误实参。
- 与 `umat-hierarchical-validation` 的区别：完整接触/边值模型同时含多种故障来源时，后者先分层；只有证据指向 UMAT 数据流，本 skill 才接管最小复现。修复后再回到分层验证。
- 与 `umat-props-statev-contract` 的区别：后者定义版本化槽义和迁移；本 skill 用最高访问下标、实际读写和分支赋值找实现是否违反已定义契约。

---

## E — 可执行步骤 (Execution)

1. **冻结来源身份并判定能否继续**
   - 记录原始容器/路径、抽取或 OCR 过程、SHA、编码、缺失卷/对象、许可和可信原件；逐行检查非代码字符串、乱码、截断与重复副本。
   - 完成标准：每个待编译文本都能回指可信来源，且“源码事实/文档片段/构建产物”角色分开。
   - 判停条件：发现 U08 式文本插入、缺卷、无法消歧的 OCR 符号或无权使用的源码时，隔离文件并请求原件；不要猜修后运行。

2. **冻结源格式、工具链与依赖**
   - 按目标编译器确认 fixed/free form、续行列、行长、字符编码、预处理、`ABA_PARAM.INC/aba_param.inc`、编译器指令和 Abaqus ABI；列出每个外部符号、库、版本、许可与返回状态。
   - 对旧 `F01AAF` 等依赖先证明库可用和接口匹配；若替换为 LAPACK，视为代码变更并重新验证，不做静默名称替换。
   - 完成标准：形成可复现构建清单；所有 include/外部符号均可解析，格式检查无截断/错续行，依赖错误会在链接前被报告。
   - 判停条件：缺库、旧 ABI 或许可证未解时，停止材料算法调试并报告构建阻断。

3. **执行宿主接口与数组静态门**
   - 给接口参数标注 input/output/update；盘点 `PROPS/STATEV` 最高下标、局部数组形状、`NDI/NSHR/NTENS` 分支、所有返回路径和深层退出。启用 `IMPLICIT NONE`、显式接口、数组边界、未初始化与警告检查。
   - 拒绝改写按目标手册定义为输入的 `STRAN/charLength` 等宿主数据；为 VUMAT 每个材料点成套赋 `stressNew`、全部 `stateNew` 和所需能量，未变化槽从 old 复制。
   - 完成标准：任何接口组合都不会越界；每个被 reduction/分支读取的局部槽先赋值；正常/失败返回均有完整输出集合和事务语义。
   - 判停条件：来源仍有越界、未初始化、输入改写、漏赋输出或无控制的 `XIT/xplb_exit` 时，先修静态阻断，不提交 Abaqus 作业。

4. **分类故障并构造最小复现**
   - 静态门通过后，从首个日志错误或异常增量开始，缩为单积分点/单单元、少增量、固定参数和确定加载；关闭无关接触、并行噪声与后处理。
   - 分成来源/构建、接口/数组、状态事务、数学角色、非有限数和全局收敛六类，不在分类前改公式。
   - 完成标准：同一输入稳定复现同一首个异常，输出量小到可逐调用审查；来源/构建问题不再混入运行期问题。

5. **建立语义账本并设置六个检查点**
   - 为关键量记录代码名、数学对象、形状、单位、坐标/Voigt、读写方向和状态层级；至少覆盖 `STRESS/STRESST`、`STATEV`、`DSTRAN`、`F/dF/dG`、`De/DDSDDE`、`Δλ`、事件/失败标志及宿主输出。
   - 在入口、弹性试算后、分支后、每轮局部更新后、原子提交前和返回前记录少量不变量。
   - 完成标准：实参与形参逐项匹配；一次运行生成按调用/增量排序的状态转移表，且 predictor、candidate、committed 和返回量可区分。

6. **沿首个偏差二分追踪**
   - 从最早不满足预期的两个检查点之间继续细分；必要时 Step Into 子程序，比较进入/退出时的语义账本。
   - 优先检查旧态/当前态混用、标量/向量错传、错误早退、分支漏赋、未初始化和隐式类型；不要先在最终云图处调参。
   - 完成标准：定位到第一条使对象、形状、层级或不变量失配的赋值/调用，并有前后值证据。
   - 失败路径：若交互式附加不可用，改用离线材料点驱动器或受限日志；若日志改变时序，降低输出频率并固定单线程复现。

7. **做最小修复与双重回归**
   - 只修复已证实的语义断点，并打开 `IMPLICIT NONE`、数组边界/未初始化检查和可用的接口诊断；重新运行最小复现及一个相邻正常路径。
   - 完成标准：首个偏差消失、相邻正常路径不退化，且提交/回滚/返回不变量全部通过。
   - 判停条件：若修复只靠改变容差、减小增量或加入稳定化才能隐藏偏差，不算完成，继续追踪根因。

8. **清理调试钩子并移交验证**
   - 移除或关闭 `READ *`、高频 `WRITE`、临时硬编码路径和调试编译选项；保留可配置断言与最小回归案例。
   - 按目标 Abaqus、编译器和 IDE 版本重新发现进程、符号与配置，不复制旧版路径。
   - 完成标准：批处理/并行运行不会等待键盘输入或产生失控日志；静态门和最小回归均通过，随后进入 `umat-hierarchical-validation`。

---

## B — 边界 (Boundary)

### 不要在以下情况使用此 skill

- 需要证明材料模型物理正确、参数可识别或边值响应可信：语义调试只证明数据流按设计执行。
- 需要推导 CPA、损伤律或一致切线：先使用相应算法/审计 skill，再以本 skill 定位实现偏差。
- 仅因某版本工具链无法关联便修改本构公式；工具配置问题与材料数学必须分开。
- 只要做通用 Fortran 风格整理、许可证法律结论或恶意代码安全审计且不涉及 Abaqus 宿主数据流时；本 skill 不是通用代码审计器。
- 已确定源码有无法消歧的 OCR/文本污染、缺失外部库或不兼容 ABI 时；应先取得可信原件/依赖，而不是绕过静态门运行。

## 相关 skills

- **depends-on**: 无——只要已有可复现的错误数据流就可启动语义定位。
- **contrasts-with**: 无——错误定位与修复后验证是先后组合，不是二选一方案。
- **composes-with**: `umat-hierarchical-validation`——先定位并修复首个语义偏差，再用独立基准逐层验证。

---

## 公开版说明

本公开版只保留作者重新组织的机制边界、执行步骤和相邻 skill 路由。所有第三方原始材料及内部中间文件均已排除。
