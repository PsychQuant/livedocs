## 1. 通用 pin 層（universal pin layer，TDD）

- [ ] 1.1 為通用 pin 層寫 failing 單元測試（RED），涵蓋 asdf `.tool-versions`、mise 設定檔、慣用 per-language version 檔（`.python-version` / `.nvmrc` / `.ruby-version`）的解析，落實設計「兩層架構：通用 pin 層加上 depth adapter 層」的 pin 層部分。驗證：`Tests/LiveDocsCoreTests/RuntimeIntrospectionTests.swift` 中對應測試先失敗。
- [ ] 1.2 在 `Sources/LiveDocsCore/RuntimeIntrospection.swift` 實作通用 pin 層 parser 使 1.1 轉綠，交付 `Two-layer resolution with a universal pin layer and per-language depth adapters` 需求的 pin 層行為：輸入 cwd、輸出各來源命中的宣告版本。驗證：1.1 測試轉綠。

## 2. 結果型別、precedence 與誠實回報

- [ ] 2.1 [P] 為 `Active-toolchain-authoritative precedence` 寫 failing 測試（RED），以設計「Precedence 通則：active toolchain 為權威、宣告只作 cross-check」的表格值（venv 3.12 + requires-python >=3.9 → 3.12；swift-tools-version 5.9 + swift 6.0 → 6.0）為 fixtures。驗證：對應測試先失敗。
- [ ] 2.2 實作結果型別與 precedence 排序使 2.1 轉綠，交付 `Read-only effective runtime version resolution` 的結果形狀（resolved 帶 version/source/semantics/env）與 `Active-toolchain-authoritative precedence`（constraint 只當下限、directive 記為宣告、language-mode 不當版本）。驗證：2.1 轉綠。
- [ ] 2.3 [P] 為 `Honest not-resolved fallback and cwd-project-scoped resolution` 寫測試並實作：無來源時回 not-resolved 帶 reason、cwd-project-scoped 解析、絕不回誤導性全域版本。驗證：對應 not-resolved / cwd-scoped 測試綠。
- [ ] 2.4 [P] 為 `Boundary validation of runtime targets` 加 `isSafe*` 驗證與測試：不安全的語言名 / target 被拒、不進命令執行。驗證：injection fixture 測試綠。

## 3. depth adapter 抽象與初始語言集

- [ ] 3.1 實作 per-language depth adapter 抽象（detect / sources / probeActive / isSafe），交付設計「初始 depth adapter 集與通用 pin 層來源」的 adapter 介面契約。驗證：抽象的 fixture 測試綠。
- [ ] 3.2 實作並測試 `Initial depth-adapter language coverage` 的 7 個 adapter（Python、Node/TypeScript、Go、Rust、Java、C#/.NET、Swift），Swift 以本 repo 自身 dogfood 一則。驗證：7 個 adapter 各自 detect / precedence fixture 測試綠，Swift dogfood 測試綠。

## 4. MCP runtime kind

- [ ] 4.1 在 `Sources/CheLiveDocsMCP/RuntimeIntrospect.swift` 實作 MCP 側 active toolchain 探測（injection-guarded，比照既有 RIntrospect），交付設計「MCP 只新增 read-only kind、detect/surface 編排留在 docs-router skill」的 MCP 探測部分。驗證：整合呼叫回實跑版本且為 read-only。
- [ ] 4.2 在 `Sources/CheLiveDocsMCP/Server.swift` 的 `introspect` kind enum 與 dispatch 新增 runtime kind，交付端到端 `Read-only effective runtime version resolution` 工具行為。驗證：kind=runtime dispatch 走 runtime 路徑、不執行任何安裝。

## 5. docs-router detect / surface 觸發

- [ ] 5.1 在 `plugins/livedocs/skills/docs-router/SKILL.md` 改寫觸發模型，交付 `Context-aware reconciliation trigger`：detect（eager + per-cwd 快取 + silent）與 surface（lazy + relevant）兩相，落實設計「觸發拆分：detect 為 eager 快取靜默、surface 為 lazy 且僅在相關時」與「per-cwd runtime 快取與失效」，且 defer-to-local 不變。驗證：skill 文件 review 覆蓋 detect、surface、per-cwd cache、defer-to-local 四點。

## 6. 收尾與 audit

- [ ] 6.1 [P] 更新 `CHANGELOG.md` 與 `README.md`，交付對外可見的新 runtime introspection kind + detect/surface 觸發說明。驗證：內容 review 對齊 proposal 的 What Changes。
- [ ] 6.2 跑完整 `swift test` 全綠並做 audit：確認 not-resolved 誠實、MCP read-only、無把 constraint 當版本的錨錯路徑。驗證：`swift test` 全綠 + audit checklist 逐條過。
