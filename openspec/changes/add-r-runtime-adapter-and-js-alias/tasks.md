## 1. R depth adapter（TDD）

- [x] 1.1 測試先行（RED）：Tests/LiveDocsCoreTests/RuntimeIntrospectionTests.swift 新增 R 案例 — firstVersionToken 對 "R version 4.4.1 (2024-06-14)" 與 "Rscript (R) version 4.4.1" 皆回 "4.4.1"；parseRDescription 對 "Depends: R (>= 4.1.0)" 回 "4.1.0"、對缺 Depends/無 R 條目回 nil；detectLanguages 對含 DESCRIPTION / renv.lock / .r-version / foo.Rproj 的檔案集合回含 .r。驗證：新測試先 FAIL（parseRDescription 與 case r 未存在）。
- [x] 1.2 GREEN：Sources/LiveDocsCore/RuntimeIntrospection.swift — RuntimeLanguage 加 case r；detectLanguages 加 R 訊號（any(["DESCRIPTION", "renv.lock", ".r-version"]) 或 anySuffix([".Rproj"])）；新增 parseRDescription（讀 Depends 欄位的 R (>= x.y) → 版本字串，constraint 用）。Sources/CheLiveDocsMCP/RuntimeIntrospect.swift — adapter(for: .r) 回 Adapter(idiomaticFile: ".r-version", manifestFile: "DESCRIPTION", manifestParse: parseRDescription, manifestSemantics: .constraint, probeCommands: ["R", "Rscript"], probeArg: "--version")；toolNames(for: .r) 回 ["r"]。交付 spec requirement「Initial depth-adapter language coverage」（8 語言含 R）。驗證：1.1 全數轉綠、既有 110 tests 不回歸。

## 2. javascript→node alias（TDD）

- [x] 2.1 測試先行（RED）：resolve(cwd:languageId:"javascript") 在 node adapter 可解析的環境回 languageId=="javascript" 且 resolution 為 node adapter 結果（source 含 node probe 或 node pin 來源）；node 不可解析時回 notResolved（與 target node 行為一致、不捏造）。驗證：先 FAIL。
- [x] 2.2 GREEN：Sources/CheLiveDocsMCP/RuntimeIntrospect.swift 的 resolve() — languageId=="javascript"（case-insensitive）時以 .node adapter 解析、LanguageResult.languageId 保留 "javascript"。交付 spec requirement「JavaScript language identifier aliases to Node」。驗證：2.1 轉綠。

## 3. 對外文件同步

- [x] 3.1 [P] Sources/CheLiveDocsMCP/Server.swift 的 introspect 工具描述 — 語言清單加 R、註明 javascript aliases to node。驗證：swift build 過 + 描述字串 grep 到 R 與 alias。
- [x] 3.2 [P] plugins/livedocs/skills/look-up/SKILL.md — Explicit invocation 的 Language 段落與 Version reconciliation 段落：R 改為 supported（移除「R has no runtime adapter」降級文字、保留其他無 adapter 語言的 not-resolved 誠實路徑）、javascript alias 措辭改引擎層；Shape examples 的 R 列改 anchored。交付 spec requirement「Explicit invocation routes deterministically by argument shape」的 MODIFIED Language 條款。驗證：內容審查對照 explicit-doc-lookup MODIFIED delta 的 Example 表逐列一致；grep SKILL.md 無「no R runtime adapter」殘留。
- [x] 3.3 [P] CHANGELOG.md 新 entry（Unreleased 或版本標題由 release train 決定）：R depth adapter + javascript alias，註明 binary 發布與 #36 共 train。驗證：git diff 僅新增行。

## 4. 全量驗證

- [x] 4.1 swift test 全綠（110 + 新增 R/alias 測試）；grep 驗證 spec deltas 與 SKILL/Server 描述一致（8 語言清單三處同步：兩 spec + Server 描述）。
- [ ] 4.2 發布鏈（post-merge step，非 merge blocker）：與 #36 共用一次 make release-signed + binary_version bump + marketplace 同步；本 change merge 時不執行。驗證：PR merge 後由 release train issue/checklist 追蹤。
