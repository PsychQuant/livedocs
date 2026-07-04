> [English](Testing) | 繁體中文

# 測試

LiveDocs 有兩套獨立 test suite —— **197 個 test,全綠**。Swift suite 驗證引擎;Python suite
驗證 `look-up` *skill* 是否真的會激起 LiveDocs 查詢並給出現行答案, 外加 vs-context7 比較
harness。以下計數是快照;真正的 source of truth 是實際跑一次。

```bash
swift test                                  # 144 個 Swift test
python3 -m pytest evals/look-up/tests/  # 53 個 Python eval test
```

## Swift — 144 個 test（`swift test`）

依 pure-core / MCP-shell 架構分兩層。`LiveDocsCore` 無依賴、不碰網路(HTTP 用 fake 注入);
`CheLiveDocsMCP` 覆蓋 process 與檔案系統層。

### `LiveDocsCoreTests` — 115（純邏輯）

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `RuntimeIntrospectionTests` | 30 | 語言 runtime 偵測:pin parser(`.tool-versions`、mise、idiomatic `.<lang>-version`)、precedence engine(active toolchain 權威)、mise 註解/陣列拒絕、多行/alias 拒絕、R toolchain banner 解析 + DESCRIPTION `Depends` constraint、javascript→node 先正規化再過安全閘。 |
| `RegistryAdaptersTests` | 15 | 9 個 registry 的 parser(npm / PyPI / crates / go / rubygems / JSR / packagist / maven / CRAN)、三個 per-version confirm parser(crates/go/rubygems pin)、supportsVersionPin 覆蓋。 |
| `URLSafetyTests` | 9 | SSRF guard:scheme allowlist + loopback / link-local（`169.254`）/ RFC-1918 / ULA / metadata host 判定。 |
| `TextSanitizeTests` | 7 | 對 fetched 內容的 control / ANSI / OSC / bidi / zero-width 過濾 + UTF-8 byte 截斷。 |
| `LLMSTxtTests` | 6 | `llms.txt` 候選排序、soft-404 content-type guard、index/full 版本切分。 |
| `IntrospectionTests` | 6 | OpenAPI / GraphQL schema 解析(method allowlist、只取 shape、輸出確定排序)。 |
| `RIntrospectionTests` | 6 | 已裝 R 套件版本解析 + 安全套件名驗證。 |
| `EngineTests` | 12 | 用注入的 HTTP fake 跑 discovery chain(registry → llms.txt → repo)、非 npm/pypi 版本 pin honoring(pin_honored true/false/nil)、latest-only ecosystem engine 端設 pin_honored=false、auto-detect 兩段 pin 解析(先 npm→PyPI 找 exact pin,pin 到處都無時 fall back npm latest+false)。 |
| `ETagCacheTests` | 5 | ETag 重驗語意(304 → 用 cache、200 → 更新、絕不 blind-stale、POST 不 cache)。 |
| `RegistryTests` | 5 | 各生態 registry 解析 + 版本 pin。 |
| `ClassificationTests` | 4 | soft-404 命中/未命中分類。 |
| `ETagCacheLRUTests` | 4 | cache 有界(LRU 淘汰、byte 預算、過大 entry 拒收)。 |
| `ValidationTests` | 4 | 邊界驗證(package/version 字串無法注入 URL 結構)。 |
| `RankingTests` | 2 | fidelity → freshness 排序 + 穩定 tiebreak。 |

### `CheLiveDocsMCPTests` — 29（process / 檔案層）

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `RuntimeIntrospectTests` | 11 | symlink 版本檔拒絕(防機密外洩)、未覆蓋語言 fallback 到 universal pin layer、canonical `mise.toml`、PATH-first executable 解析、大寫 id 接受且保留請求原 id(R / JavaScript)、javascript↔node 解析等價。 |
| `ProcessRunnerTests` | 4 | 大輸出不 deadlock(並發讀 pipe)、exit code 浮現、timeout 回報、SIGTERM→SIGKILL escalation。 |
| `LatestVersionEncodingTests` | 14 | `latest_version` 工具邊界:pin_honored true/false/nil surfacing(含 nothing-resolved 路徑的 false、無 pin 時缺席)、Go `v`-prefix 已確認 pin(不可誤判成 not-applied)、v-prefix 輸入建出正確 confirm URL、npm 找不到→latest+false、npm dist-tag/exact-pin 區分(移動 tag 絕不假裝成 pin)、RubyGems 端到端 pin(honored + not-found)。 |

## Python — 53 個 test（`pytest evals/look-up/`）

`look-up` **skill eval harness** —— 不是測 Swift 引擎,而是測 skill 對多種 prompt 會不會
激起 LiveDocs 查詢並答對現行 —— 外加 vs-context7 比較 harness。見
[`evals/look-up/README.md`](https://github.com/PsychQuant/livedocs/blob/main/evals/look-up/README.md)。

| 檔案 | 數 | 測什麼 |
|------|---:|--------|
| `test_run_eval.py` | 17 | rate 門檻判定、N=3 門檻塌縮 guard、failed-run / inconclusive 處理、explicit route 比對、`args_match`——對的工具但錯的參數(mis-split `name@version` / 掉 ecosystem pin)判為不正確。 |
| `test_compare.py` | 15 | vs-context7 新鮮度 harness:版本 token 比對(邊界形式)、對稱計分、表格＋長條圖 render、README emit-block 漂移守衛、corpus↔sample 同步。 |
| `test_oracle.py` | 8 | `self_check`(eval 時打 registry —— 防腐爛)/ `structural` / `golden` oracle。 |
| `test_detect.py` | 9 | `claude -p` stream-json 解析、`is_error` 偵測、LiveDocs 觸發訊號辨識、逐 call 工具輸入捕捉(short name + input args)。 |
| `test_corpus.py` | 4 | corpus 覆蓋守衛(存在一個 golden case + 一個 library-named 對抗負面案例 + explicit /livedocs:look-up 各 argument shape 都有代表案例 + arg-sensitive 案例 pin 住 `expected_args`)。 |

## CI 與 release gate

- **CI** 每個 push / PR 跑 `swift build` + `swift test`。
- **`scripts/release.sh`** 把 release gate 在:`swift test` 綠、版本 source 與 tag 相符、
  Developer ID 簽章 + notarize。
- **Python eval** 是 periodic / manual,不進 per-PR CI —— 它會真的呼叫 `claude -p`(有成本 +
  stochastic),所以當 maintainer baseline 跑,不放關鍵路徑上。

## 紀律

安全與健壯性關鍵面都是 test-first(TDD)建的:`URLSafety`、`TextSanitize`、`ProcessRunner`、
eval harness 都先有失敗的 test 才寫實作。v0.7.0 hardening 期間 Swift test 從 72 → 110(補上
之前沒測的 MCP shell 層),Python eval 從 0 → 50(skill eval + vs-context7)。
