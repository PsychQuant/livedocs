## Why

LiveDocs 目前只查 web 最新版，對「同時有 web-latest 與本機已裝版」的 target 沒有版本感知 → version-skew bug（照 latest 文件操作，本機版本沒那個 API / 行為不同）。且並非所有 target 都有本機版本（Claude Code 功能·設定、SaaS 只有線上 docs），需先分類再決定流程。

## What Changes

- 新增 **per-question target-type 分類**：判斷「這個查詢有沒有 local, version-matched 權威源」，路由到兩條路徑。
- **has-local** 路徑：版本協調 state machine —— 查本機已裝版（cwd-scoped）→ 比對 web latest：相同或不升 → 以 local 為準；web 較新且使用者確認 → 安裝（由 skill/model 執行 + 確認）→ 以 local 為準。**不變式：終點恆為「以 local 為準」；web 只 gate 升級決策。**
- **web-only** 路徑（Claude Code 功能·設定、SaaS、hosted docs）：直接查 web latest，不協調、不問升級。
- 新增 MCP `introspect` 的 **installed-version mode（read-only）**：查本機已裝套件/CLI 的版本（+ help），cwd-project-scoped 解析環境。
- 觸發為 **context-aware**：僅在「在用到該套件的專案內」或「版本/升級/debug 形狀的問題」時進協調。
- context7 維持外部 reference（不整合進 binary）。

## Capabilities

### New Capabilities

- `target-type-classification`: per-question 判斷 has-local vs web-only，並據以路由。
- `version-reconciliation`: has-local 的版本協調 state machine（context-aware 觸發 + install 由 skill 執行 + 終點恆以 local 為準不變式）。
- `installed-version-introspection`: MCP read-only 查本機已裝版本（cwd-scoped env 解析）。

### Modified Capabilities

<!-- none — 全新 change，無既有 spec 需改 -->

## Impact

- `docs-router` skill：加 classifier + 兩路分支 + 協調 state machine 編排 + install 確認流程。
- `CheLiveDocsMCP` 的 `introspect`：加 installed-version mode（維持 read-only）。
- 無 BREAKING（純新增行為）；context7 定位不變（外部 reference）。
