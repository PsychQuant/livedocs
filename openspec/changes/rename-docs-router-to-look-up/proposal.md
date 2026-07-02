## Why

livedocs plugin 唯一的 skill 名稱 docs-router 描述的是內部機制而非使用者動作 — 連 plugin 作者本人都認不出它是什麼（PsychQuant/livedocs#32）。Skill 在 Claude Code 預設本就雙模式（implicit 自動觸發 + 顯式 /livedocs:docs-router），但這個名字讓顯式入口毫無可發現性，且缺乏帶參數呼叫時的路由契約。

## What Changes

- **BREAKING**：skill 改名 docs-router → look-up（目錄 plugins/livedocs/skills/docs-router/ 改為 plugins/livedocs/skills/look-up/，SKILL.md 的 name 欄位同步）。顯式呼叫名由 /livedocs:docs-router 變為 /livedocs:look-up。frontmatter description 維持問題導向原文不動 — implicit 觸發由 description 驅動，rename 不影響 auto-fire。
- SKILL.md 新增「Explicit invocation」段落：定義 $ARGUMENTS 依參數形態的確定性路由 — 語言名（R、python 等）走 runtime introspection 並錨定語言文件；套件名（可帶 name@version）走 resolve_source 再 fetch_docs；URL 走 OpenAPI/GraphQL introspection；CLI 命令名走 CLI introspection；無參數則載入既有路由指引（行為同 implicit）。
- 名稱引用面同步：CLAUDE.md、README.md、docs/positioning.md、.claude-plugin/marketplace.json 與 plugins/livedocs/.claude-plugin/plugin.json 的 description、plugins/livedocs/README.md、三對雙語 wiki 頁（Home、Primary-Source-Spectrum、Testing 各 en 與 zh-TW）。
- eval harness 目錄連動改名 evals/docs-router/ 改為 evals/look-up/（docstring 與註解內名稱同步；CLAUDE.md 與 README 內 pytest 路徑連動更新）。
- CHANGELOG.md 新增 entry 記錄 breaking rename；歷史 entries 不改寫。
- 發布鏈：plugin 版本 0.7.0 → 0.8.0（純 plugin shell 變更、無 binary 重發），marketplace 同步。

## Non-Goals

- 不改 implicit 路由決策流程的行為（per-question 分類、version reconciliation 邏輯全數不動）。
- 不新增其他 skill（freshness 候選另由 PsychQuant/livedocs#33 追蹤）。
- 不改寫歷史紀錄：CHANGELOG 既有 entries、openspec/changes/archive/ 內容、既有 specs 的 @trace provenance 區塊保留舊路徑字串（審計軌跡）。
- 不動 MCP binary（resolve_source、fetch_docs、latest_version、introspect 四個 tools 無變更，不需簽章發布流程）。

## Capabilities

### New Capabilities

- `explicit-doc-lookup`: 顯式帶參數文件查詢契約 — /livedocs:look-up 的 $ARGUMENTS 形態判定與確定性路由（語言、套件、URL、CLI、無參數五種形態），並保證 rename 不改變 implicit 觸發行為。

### Modified Capabilities

(none — installed-version-introspection、target-type-classification、version-reconciliation 三個 specs 內的 docs-router 字串皆位於 @trace provenance 註解區塊，屬歷史軌跡，刻意不改)

## Impact

- Affected specs: explicit-doc-lookup（新增）
- Affected code:
  - New: plugins/livedocs/skills/look-up/SKILL.md（由改名而來）、evals/look-up/（由改名而來，含既有 harness 全部檔案）
  - Modified: CLAUDE.md、README.md、docs/positioning.md、.claude-plugin/marketplace.json、plugins/livedocs/.claude-plugin/plugin.json、plugins/livedocs/README.md、docs/wiki/Home.md、docs/wiki/Home-zh-TW.md、docs/wiki/Primary-Source-Spectrum.md、docs/wiki/Primary-Source-Spectrum-zh-TW.md、docs/wiki/Testing.md、docs/wiki/Testing-zh-TW.md、CHANGELOG.md、evals/look-up/README.md、evals/look-up/detect.py、evals/look-up/run_eval.py、evals/look-up/oracle.py、evals/look-up/corpus.yaml、evals/look-up/requirements.txt
  - Removed: plugins/livedocs/skills/docs-router/SKILL.md、evals/docs-router/（皆為改名之來源路徑）
