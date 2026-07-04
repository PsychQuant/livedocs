## Why

look-up 的旗艦例 `/livedocs:look-up R` 目前只能走誠實降級（not-resolved → web-latest）：引擎的 RuntimeLanguage enum 沒有 r，resolveGeneric 只讀 pin 檔、不 probe toolchain，而典型 R 專案（renv / DESCRIPTION）不用 asdf/mise pin。`javascript` 亦無 alias 到 node，永遠 notResolved（PR #34 verify 實證；PsychQuant/livedocs#35）。

## What Changes

- RuntimeLanguage enum 新增 case r；adapter：probeCommands ["R", "Rscript"]（順序 fallback）+ probeArg --version、idiomaticFile .r-version、manifestFile DESCRIPTION（新增 parseRDescription 讀 Depends: R (>= x)，依既有 **constraint** semantics 不當 exact）
- detectLanguages 新增 R 訊號：DESCRIPTION + NAMESPACE 同時存在（裸 DESCRIPTION 訊號太弱、非 R 專案也可能有），或 renv.lock / .r-version 任一存在，或 *.Rproj / *.rproj 後綴
- 版本解析不需新 parser：既有 firstVersionToken 已覆蓋 "R version 4.4.1 (…)" 與 "Rscript (R) version 4.4.1" 兩種輸出（以測試鎖定）
- resolve() 入口 javascript → node alias：languageId 回傳請求原 id "javascript"，resolution 走 node adapter（source 欄位天然揭露 node probe，零 schema 變更）
- Spec MODIFIED deltas ×2：runtime-version-introspection 的 coverage requirement（7 → 8 語言 + alias 條款）；explicit-doc-lookup 的 Language 路由 requirement（R 改 supported、alias 措辭、not-resolved 降級對其他無 adapter 語言保留）
- 同步：plugins/livedocs/skills/look-up/SKILL.md 語言段落、Sources/CheLiveDocsMCP/Server.swift 工具描述、CHANGELOG.md 新 entry
- Binary 變更：簽章發布與 binary_version bump 為 post-merge step，與 #36 共用一次 release train（本 change 不執行發布）

## Non-Goals

- 不做 Windows 的 R probe 支援（macOS/Linux 輸出格式為準）
- 不讀 DESCRIPTION 的 Depends 以外欄位（Imports/Suggests 與 runtime 版本無關）
- 不新增 resolved_as 之類 response schema 欄位（alias 揭露由既有 source 欄位承擔）
- 不在本 change 執行 make release-signed / marketplace 同步（與 #36 合併 release train，post-merge）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `runtime-version-introspection`: Initial depth-adapter language coverage requirement 從 7 語言擴為含 R 的 8 語言，並新增 javascript→node alias 的 normative 條款與 scenarios
- `explicit-doc-lookup`: Language 路由 requirement 更新 — R 由 not-resolved 降級範例改為 supported、javascript alias 行為引用引擎層 alias、not-resolved 誠實降級對其餘無 adapter 語言保留

## Impact

- Affected specs: runtime-version-introspection（MODIFIED）、explicit-doc-lookup（MODIFIED）
- Affected code:
  - Modified: Sources/LiveDocsCore/RuntimeIntrospection.swift、Sources/CheLiveDocsMCP/RuntimeIntrospect.swift、Sources/CheLiveDocsMCP/Server.swift、Tests/LiveDocsCoreTests/RuntimeIntrospectionTests.swift、plugins/livedocs/skills/look-up/SKILL.md、CHANGELOG.md
  - New: (none)
  - Removed: (none)
