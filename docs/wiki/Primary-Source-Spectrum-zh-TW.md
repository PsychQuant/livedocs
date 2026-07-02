> [English](Primary-Source-Spectrum) | 繁體中文

# Primary-Source 光譜 — LiveDocs 是什麼、不是什麼

產品邊界的 source of truth。對應已歸檔的 change `add-target-type-version-reconciliation` 與它的 living specs(`target-type-classification`、`version-reconciliation`、`installed-version-introspection`)。

## 原則

LiveDocs 是 primary-source-first: 任何文件問題, 都去找權威、version-matched 的 primary source, 不用參數記憶(stale), 也不用預建的 lossy 索引(context7)。讓這件事 scale 的一般化是: 「primary source 在哪」依 target 類型決定, 不是假設它永遠在 web。

## 光譜

| 目標類型 | primary source 在哪 | 怎麼解析 | 歸誰 |
|---|---|---|---|
| 第三方公開 library / tool / API | remote(registry / `llms.txt` / repo / OpenAPI / GraphQL), 而且模型的記憶是 stale | LiveDocs auto-discovery chain | LiveDocs(價值最高) |
| 已裝套件 / CLI | 本機已安裝的 artifact | `introspect`(`cli` / `r-pkg`; npm/pip 待做) | LiveDocs(read-only) |
| Web-only hosted docs / SaaS(如 Claude Code 功能設定) | remote、只有 latest(無本機版) | 直接查 web-latest, 不協調 | LiveDocs(`look-up` web-only 分支) |
| 你自己 / 私有 / 內部程式碼 | 本機原始檔(working tree, 永遠最新) | 直接讀檔 | coding agent(不是 LiveDocs) |

## LiveDocs 價值集中在哪

集中在「primary source 在 remote, 而模型那份 stale」(第三方相依)。對 primary source 在本機、可直接讀的程式碼(你自己的 repo), agent 讀檔就已經拿到 primary source, LiveDocs 的 fetch 層在這裡加值有限。

## 邊界 — LiveDocs 不做什麼

- 私有 / 內部 / 閉源程式碼: 沒有公開的權威源; source of truth 是本機 codebase 本身。讓 LiveDocs 去 RAG 私有 repo, 會跟 coding agent 已經在做的(讀 code)重疊。這是刻意的 out of scope, 不是缺功能。
- 你當前專案自己的程式碼: 讀檔。

## 分工 — 兩者互補

一個任務沿著「primary source 在哪」自然拆開。debug 你自己用了 FastAPI 的程式碼: agent 讀你的檔(local primary), 用 LiveDocs 查 FastAPI(external primary)。LiveDocs 管 external/remote 那半, agent 讀檔管 local 那半。合起來就是完整覆蓋, 誰都不該吞掉對方。

## 仍在 scope 內的缺口

非機器可讀的第三方文件(只有 PDF、登入牆 wiki、影片、Discord)會退化到 repo README 或 nothing。這個邊隨 `llms.txt` 普及在縮小(2026-06 時約 88% 熱門 docs host 已 ship)。
