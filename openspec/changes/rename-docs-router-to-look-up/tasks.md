## 1. Skill 改名與顯式呼叫契約

- [x] 1.1 將 plugins/livedocs/skills/docs-router/ 目錄改名為 plugins/livedocs/skills/look-up/，並把 SKILL.md frontmatter 的 name 改為 look-up、description 逐字保留 — 交付 spec「Rename preserves the implicit triggering contract」：安裝後 skill 以 /livedocs:look-up 顯式可呼叫、implicit 觸發語意不變。驗證：git diff 顯示 frontmatter 內僅 name 行變動、description 行 byte-identical（H1 標題與新段落屬 1.2 範圍）；grep 確認 plugins/livedocs/skills/ 下不再出現 docs-router；本機以 claude --plugin-dir plugins/livedocs 啟動後 skill 清單出現 look-up 且無 docs-router。
- [x] 1.2 在 plugins/livedocs/skills/look-up/SKILL.md 新增「Explicit invocation」段落 — 交付 spec「Explicit invocation routes deterministically by argument shape」與「Explicit invocation without arguments degrades to routing guidance」：含 $ARGUMENTS placeholder、分類優先序（URL → 語言固定集 → 套件（含 name@version）→ CLI fallback）、後續 token 作 topic filter、無參數時等同 implicit 載入路由指引。驗證：內容審查逐項對照 spec 四個 scenario 與 Example 分類表（R / react@18 / dplyr mutate / https URL / gh 五列全數對應）。

- [x] 1.3 在 SKILL.md Explicit invocation 段落明文標注 URL/CLI targets 仍受引擎層 guards 約束 — 交付 spec「Explicit targets remain subject to engine-layer guards」：SSRF host classifier 與 CLI 安全 allowlist/argv-only 執行為既有 0.7.0 引擎行為（本 change 不動 binary），skill 層僅加路由、不構成 bypass。驗證：SKILL.md 含該聲明句；引擎 guard 行為由既有 110 Swift tests（SSRF guard / CLI introspect 測試）覆蓋，本 change 無 Sources/ diff。

## 2. 引用面同步

- [x] 2.1 [P] 將 evals/docs-router/ 目錄改名為 evals/look-up/，並同步 detect.py、run_eval.py、oracle.py、corpus.yaml、requirements.txt、README.md 內的 docs-router 名稱 — 交付：harness 自我描述與新 skill 名一致、路徑可用。驗證：python3 -m pytest evals/look-up/tests/ 全數 41 tests green；grep evals/ 零 docs-router 命中。
- [x] 2.2 [P] 更新 CLAUDE.md、README.md、docs/positioning.md 的 skill 名稱與 evals 路徑 — 交付：文件中的命令可逐字複製執行（pytest 與 run_eval.py 路徑指向 evals/look-up/）。驗證：實際執行文件中列出的 pytest 命令通過；grep 該三檔零 docs-router 命中。
- [x] 2.3 [P] 成對更新 docs/wiki/Home.md、docs/wiki/Home-zh-TW.md、docs/wiki/Primary-Source-Spectrum.md、docs/wiki/Primary-Source-Spectrum-zh-TW.md、docs/wiki/Testing.md、docs/wiki/Testing-zh-TW.md — 交付：三對雙語頁的 skill 名稱與 eval 路徑一致（repo 雙語成對慣例）。驗證：grep docs/wiki/ 零 docs-router 命中；每對 en 與 zh-TW 頁逐對內容審查確認提及處數量一致。
- [x] 2.4 [P] 更新 .claude-plugin/marketplace.json 與 plugins/livedocs/.claude-plugin/plugin.json 的 description 文字（a docs-router skill 改為 a look-up skill）— 交付：marketplace 列表描述與實際 skill 名一致。驗證：python3 -m json.tool 兩檔皆通過；grep 兩檔零 docs-router 命中。

## 3. 版本與變更紀錄

- [x] 3.1 plugins/livedocs/.claude-plugin/plugin.json 的 version 由 0.7.0 升為 0.8.0（binary_version 維持 0.7.0），且本 repo 自身的 .claude-plugin/marketplace.json（README 教學的安裝來源）plugin entry 與 metadata 的 version 同步升 0.8.0 — 交付：兩份 manifest 版本一致反映 breaking 的 plugin shell 變更、同時表明 MCP binary 未重發。驗證：plugin.json 的 version 為 0.8.0 且 binary_version 為 0.7.0；marketplace.json 的 plugins[0].version 與 metadata.version 皆為 0.8.0。（scope 補充源自 PR #34 verify round 1 blocking finding）
- [x] 3.2 CHANGELOG.md 新增 0.8.0 entry — 交付：記錄 BREAKING rename（/livedocs:docs-router 改為 /livedocs:look-up）與新增 Explicit invocation 段落，含使用者遷移提示；歷史 entries 逐字不動。驗證：git diff CHANGELOG.md 只有新增行、零刪除行。

## 4. 全域驗證與發布

- [x] 4.1 全 repo 一致性驗證 — 交付：非歷史檔案零 docs-router 殘留、兩套測試 green。驗證：grep -r docs-router 在排除 CHANGELOG.md 歷史 entries、openspec/changes/archive/、openspec/specs/ 的 @trace 區塊、openspec/changes/rename-docs-router-to-look-up/ 之後零命中；swift test 110 tests green；python3 -m pytest evals/look-up/tests/ 41 tests green。
- [ ] 4.2 發布鏈（post-merge step — 依 IDD 慣例 pipeline 停在 verified，本 task 於 PR merge 後執行，非 merge blocker）— 交付：使用者端可經 marketplace 安裝 0.8.0 並看到 look-up。PR merge 後執行 /plugin-tools:plugin-update livedocs 同步 psychquant-claude-plugins marketplace，並跑 bash scripts/sync-wiki.sh 鏡射 wiki。驗證：marketplace 更新後 plugin entry 版本顯示 0.8.0；本機 claude plugin update 後 /livedocs:look-up 出現在 skill 清單。
