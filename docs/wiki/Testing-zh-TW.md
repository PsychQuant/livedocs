> [English](Testing) | 繁體中文

# 測試

LiveDocs 有兩套獨立 test suite —— **139 個 test,全綠**(v0.7.0 當下)。Swift suite 驗證引擎;
Python suite 驗證 `docs-router` *skill* 是否真的會激起 LiveDocs 查詢並給出現行答案。以下計數是
快照;真正的 source of truth 是實際跑一次。

```bash
swift test                                  # 110 個 Swift test
python3 -m pytest evals/docs-router/tests/  # 29 個 Python eval test
```

## Swift — 110 個 test（`swift test`）

依 pure-core / MCP-shell 架構分兩層。`LiveDocsCore` 無依賴、不碰網路(HTTP 用 fake 注入);
`CheLiveDocsMCP` 覆蓋 process 與檔案系統層。

### `LiveDocsCoreTests` — 99（純邏輯）

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `RuntimeIntrospectionTests` | 25 | 語言 runtime 偵測:pin parser(`.tool-versions`、mise、idiomatic `.<lang>-version`)、precedence engine(active toolchain 權威)、mise 註解/陣列拒絕、多行/alias 拒絕。 |
| `RegistryAdaptersTests` | 11 | 9 個 registry 的 parser(npm / PyPI / crates / go / rubygems / JSR / packagist / maven / CRAN)。 |
| `URLSafetyTests` | 9 | SSRF guard:scheme allowlist + loopback / link-local（`169.254`）/ RFC-1918 / ULA / metadata host 判定。 |
| `TextSanitizeTests` | 7 | 對 fetched 內容的 control / ANSI / OSC / bidi / zero-width 過濾 + UTF-8 byte 截斷。 |
| `LLMSTxtTests` | 6 | `llms.txt` 候選排序、soft-404 content-type guard、index/full 版本切分。 |
| `IntrospectionTests` | 6 | OpenAPI / GraphQL schema 解析(method allowlist、只取 shape、輸出確定排序)。 |
| `RIntrospectionTests` | 6 | 已裝 R 套件版本解析 + 安全套件名驗證。 |
| `EngineTests` | 5 | 用注入的 HTTP fake 跑 discovery chain(registry → llms.txt → repo)。 |
| `ETagCacheTests` | 5 | ETag 重驗語意(304 → 用 cache、200 → 更新、絕不 blind-stale、POST 不 cache)。 |
| `RegistryTests` | 5 | 各生態 registry 解析 + 版本 pin。 |
| `ClassificationTests` | 4 | soft-404 命中/未命中分類。 |
| `ETagCacheLRUTests` | 4 | cache 有界(LRU 淘汰、byte 預算、過大 entry 拒收)。 |
| `ValidationTests` | 4 | 邊界驗證(package/version 字串無法注入 URL 結構)。 |
| `RankingTests` | 2 | fidelity → freshness 排序 + 穩定 tiebreak。 |

### `CheLiveDocsMCPTests` — 11（process / 檔案層）

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `RuntimeIntrospectTests` | 7 | symlink 版本檔拒絕(防機密外洩)、未覆蓋語言 fallback 到 universal pin layer、canonical `mise.toml`、PATH-first executable 解析。 |
| `ProcessRunnerTests` | 4 | 大輸出不 deadlock(並發讀 pipe)、exit code 浮現、timeout 回報、SIGTERM→SIGKILL escalation。 |

## Python — 29 個 test（`pytest evals/docs-router/`）

`docs-router` **skill eval harness** —— 不是測 Swift 引擎,而是測 skill 對多種 prompt 會不會
激起 LiveDocs 查詢並答對現行。見
[`evals/docs-router/README.md`](https://github.com/PsychQuant/livedocs/blob/main/evals/docs-router/README.md)。

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `test_run_eval.py` | 12 | rate 門檻判定、N=3 門檻塌縮 guard、failed-run / inconclusive 處理。 |
| `test_oracle.py` | 8 | `self_check`(eval 時打 registry —— 防腐爛)/ `structural` / `golden` oracle。 |
| `test_detect.py` | 7 | `claude -p` stream-json 解析、`is_error` 偵測、LiveDocs 觸發訊號辨識。 |
| `test_corpus.py` | 2 | corpus 覆蓋守衛(存在一個 golden case + 一個 library-named 對抗負面案例)。 |

## CI 與 release gate

- **CI** 每個 push / PR 跑 `swift build` + `swift test`。
- **`scripts/release.sh`** 把 release gate 在:`swift test` 綠、版本 source 與 tag 相符、
  Developer ID 簽章 + notarize。
- **Python eval** 是 periodic / manual,不進 per-PR CI —— 它會真的呼叫 `claude -p`(有成本 +
  stochastic),所以當 maintainer baseline 跑,不放關鍵路徑上。

## 紀律

安全與健壯性關鍵面都是 test-first(TDD)建的:`URLSafety`、`TextSanitize`、`ProcessRunner`、
eval harness 都先有失敗的 test 才寫實作。v0.7.0 hardening 期間 Swift test 從 72 → 110(補上
之前沒測的 MCP shell 層),skill eval 從 0 → 29。
