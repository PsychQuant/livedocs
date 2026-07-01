## Why

LiveDocs 的核心賣點是「the docs your code actually runs on」——回答對齊你本機實際跑的版本。但目前 `introspect` 只能查已裝套件（r-pkg）與 CLI，查不到「這個專案實際跑的是哪個語言 runtime 版本」。專案常把 runtime 釘在特定版本（pyenv 的版本檔、nvm、go.mod 的 go 指令、Package.swift 的 swift-tools-version…），回答若對到錯的 runtime 版本就會出現 version-skew：文件叫你用的語法/API，你這個版本根本沒有。

ETag revalidation 讓「保持最新」的網路成本在內容未變時趨近零，proactive（沒問就先偵測並對齊）從「loading 太重」變成可負擔——這是現在做這件事的時機。

## What Changes

- 新增 read-only 的 runtime 版本偵測，採兩層架構：
  - **通用 pin 層**：單一 parser 讀取跨語言的版本宣告來源——asdf 的 tool-versions 檔、mise 設定檔、以及各語言慣用的 per-language version 檔——一次覆蓋幾乎所有語言的「宣告版本」。
  - **depth adapter 層**：對重點語言補上 active toolchain 探測（實跑版本）與 manifest 語意判讀。初始 7 個：Python、Node/TypeScript、Go、Rust、Java、C#/.NET、Swift（Swift 兼作 LiveDocs 自身的 dogfood）。
- **Precedence 通則**：active toolchain（實際會執行的版本）為權威；宣告來源（constraint / directive / language-mode）僅用於 cross-check 或無 toolchain 時 fallback；無法解析時誠實回報 not-resolved，絕不回誤導性的全域版本。
- MCP `introspect` 新增一個 read-only 的 runtime kind。MCP 不安裝、不變更環境（沿用既有 read-only 邊界）。
- **觸發模型改動**：docs-router skill 把版本協調的觸發拆成兩相——**detect**（eager、per-cwd 快取、silent，靜默把答案錨定在有效 runtime 版本；ecosystem web-latest 靠 ETag 便宜地保持最新）與 **surface**（lazy，只在答案 version-sensitive 或實際出現 skew 時才提示升級）。defer-to-local 終端不變式維持不變。

## Capabilities

### New Capabilities

- `runtime-version-introspection`: read-only 解析專案「有效的語言 runtime 版本」。通用 pin 層（跨語言版本宣告檔）+ depth adapter 層（active toolchain + manifest 語意）；precedence 以 active toolchain 為權威；cwd-project-scoped；無法解析時誠實回報 not-resolved。

### Modified Capabilities

- `version-reconciliation`: 既有的「Context-aware reconciliation trigger」需求拆成 detect / surface 兩相。detect 因 ETag revalidation 與 per-cwd 快取而可 eager 執行且靜默錨定；surface 仍受 noise 節制、只在相關時觸發。defer-to-local 與 confirmed-install 兩條需求不變。

## Impact

- Affected specs: new `runtime-version-introspection`; modified `version-reconciliation`.
- Affected code:
  - New:
    - Sources/LiveDocsCore/RuntimeIntrospection.swift
    - Sources/CheLiveDocsMCP/RuntimeIntrospect.swift
    - Tests/LiveDocsCoreTests/RuntimeIntrospectionTests.swift
  - Modified:
    - Sources/CheLiveDocsMCP/Server.swift
    - plugins/livedocs/skills/docs-router/SKILL.md
    - CHANGELOG.md
    - README.md
  - Removed: (none)
