## 1. SKILL.md 契約同步

- [x] 1.1 在 plugins/livedocs/skills/look-up/SKILL.md 的 Explicit invocation 分類規則中，於 URL 步驟之後、Language 步驟之前插入 **Ecosystem hint** 步驟：token 形態 `<known-ecosystem>:<name>`（known-ecosystem ∈ {npm,pypi,crates,go,rubygems,jsr,packagist,maven,cran}）且 `:` 後首字非 `/` → strip 前綴、以該 ecosystem 呼叫 resolve_source、其餘 name 依 Package 規則（含 name@version pin）處理。明述其 overrides Language 遮蔽（`npm:go` 查 npm 套件 go 而非 Go runtime）與 named-only registry 具名（`cran:dplyr`）。完成定義：SKILL 分類段落含 4 形態 precedence（URL → hint → Language → Package），與 spec Requirement 1 的四形態 precedence 逐條對應。
- [x] 1.2 在 SKILL.md 的 shape examples 表新增三列 hint 範例（`npm:go`、`cran:dplyr`、`crates:serde@1.0.100`），並把既有「第一 token 等於語言名一律走 Language、要查同名套件只能用 docs URL 或散文」的遮蔽段落改寫為指向 ecosystem hint escape hatch。完成定義：`grep "npm:go" SKILL.md` 命中且原「用 docs URL 或散文」workaround 文字已改為指向 hint。

## 2. Pin scenario 對齊（#36 已出貨行為）

- [x] 2.1 在 SKILL.md 的 pin 相關措辭中，確認 crates/go/rubygems honor pin（回 pin_honored:true）、jsr/packagist/maven/cran latest-only 的描述與 spec Requirement 1 的「Version pin honesty is surfaced per ecosystem」scenario 一致（#36 已把此行為出貨、本 change 的 spec delta 一併重寫該 scenario 消除 drift）。完成定義：SKILL 無殘留「非 npm/pypi 一律 pin not applied」的舊措辭。

## 3. 發布中繼資料

- [x] 3.1 [P] 在 CHANGELOG.md 新增 [Unreleased] 或對應區塊 entry，描述 ecosystem-hint 語法（`eco:name` 前綴、precedence、disambiguation 規則）與 pin scenario 對齊。完成定義：CHANGELOG 含 hint 語法條目。
- [x] 3.2 [P] 把 plugins/livedocs/.claude-plugin/plugin.json 的 version 從 0.8.0 bump 到 0.9.0（skill 契約變更、minor），並同步 .claude-plugin/marketplace.json 的 metadata.version 與 plugins[0].version 為 0.9.0。binary_version 不動（MCP binary 不變）。完成定義：三處 version 皆為 0.9.0、binary_version 維持不變。

## 4. 驗證

- [x] 4.1 內容審查對照 spec 的 requirement「Explicit invocation routes deterministically by argument shape」：SKILL 的四形態 precedence、hint 分類規則、disambiguation（`:` 後非 `/`）、pin scenario 與 openspec/changes/add-ecosystem-hint-syntax/specs/explicit-doc-lookup/spec.md 的該 Requirement 逐條一致；`spectra validate add-ecosystem-hint-syntax` 通過。本 change 無 runtime code 變更，`swift test` 應維持 144/144 綠（回歸確認、非新增測試）。完成定義：spectra validate 綠 + swift test 144 綠 + SKILL↔spec 逐條對應無落差。
- [ ] 4.2 post-merge：merge 後跑 plugin marketplace 同步（依 release flow，把 0.9.0 推到 marketplace），此步在人工 merge 後執行、不在本 change 實作階段。完成定義：標記為 post-merge、實作階段不勾。
