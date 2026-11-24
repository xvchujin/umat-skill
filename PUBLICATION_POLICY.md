# Public Release and Copyright Policy

## Included

本仓库只发布以下原创或重新组织的内容：

- 25 个 Codex skill 的触发条件、机制边界、执行步骤和相邻 skill 路由；
- 25 个 skill 的最小 `agents/openai.yaml` 接口元数据；
- 本项目的 README、开源许可证、公开内容政策、Python/PowerShell 校验脚本和文件哈希清单。

## Excluded

以下内容不得进入公开仓库：

- 书籍、论文或标准的全文、扫描件、截图、长段摘录及排版复刻；
- 课程逐字稿、字幕、录音录像、时间码和 OCR/文档抽取全文；
- 无明确再分发许可的 UMAT/VUMAT/Fortran 源码或编译产物；
- PDF、CAJ、DOC/DOCX、PPT/PPTX、XLS/XLSX、图片、音视频和压缩包；
- Abaqus 工程输入、ODB、日志、临时作业文件或第三方材料卡；
- 私有候选语料、内部审计记录、阶段中间件、个人路径和认证信息。

## Transformation rule

公开 skill 不保留来源材料中的 Reading/原文段、逐字引文、时间码、案例复述或内部证据链接。只保留作者重新表达的技术事实、算法边界、审计步骤和路由规则。技术事实、公式和接口名称仍必须避免冒充来源授权或生产验证。

## Review gate

每次发布前必须运行 `tools/verify-public-release.ps1`，检查文件类型、路径、大小、skill 集合、frontmatter、关系 slug 和高风险内容标记。自动扫描不能替代人工版权判断；发现来源不明、许可不明或可能是长段复刻的内容时，应默认排除并留在非公开工作区。

## License status

本仓库中的公开 Markdown 内容、接口元数据与 Python/PowerShell 工具统一采用 [MIT License](LICENSE) 开源许可发布。许可证仅覆盖本仓库实际发布的原创与重新组织内容，不延伸至被排除在外的任何第三方材料。
