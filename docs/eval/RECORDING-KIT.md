# Murmur Eval 錄音手冊(只有 Panda 能做,約 20 分鐘)

> BRIEF Quality gate #1 需要一組 Apple 裝置原生錄的 fixture(iPhone 麥
> 克風 + MacBook 麥克風)。這不能用合成的，TTS 或沿用舊 clip 都違反
> BRIEF。這是整個 `/goal` 唯一沒辦法替你做的一步。其他(harness、計分、
> baseline 計算)都已經寫好驗過了。

## 你要產出什麼

10 到 20 段短語音 + 每段你實際講的逐字稿，放進
`docs/eval/fixtures/`，列在 `docs/eval/fixtures/manifest.json`。

## 建議錄音清單(12 段，刻意偏 Bug #1)

| id | 語言 | 裝置 | 講什麼 |
|---|---|---|---|
| zh-short-01..06 | 中文 | iPhone 語音備忘錄 | 6 句短中文，每句 6 字以內。這就是 Bug #1 出包的地方(短中文被轉成英文) |
| zh-long-01..03 | 中文 | MacBook 麥克風 | 3 句較長中文，15 到 25 字 |
| en-01..03 | 英文 | MacBook 麥克風 | 3 句正常長度英文 |

每段內容不同，不要講同一句兩次。正常語速講，不要刻意放慢。

## 步驟

1. **iPhone**：語音備忘錄錄每一段 `zh-short-*`，分享存成 `.m4a` 傳回
   Mac(例如丟到 `~/Desktop/murmur-rec/`)。
2. **MacBook**：用 QuickTime「新增音訊錄製」或任何錄音工具，錄
   `zh-long-*` 和 `en-*`，一樣存進 `~/Desktop/murmur-rec/`。
3. **轉成 16 kHz 單聲道 WAV**(WhisperKit 吃的格式)。沒裝就先
   `brew install ffmpeg`：
   ```bash
   cd /Users/panda/site/apps/murmur
   for f in ~/Desktop/murmur-rec/*.m4a; do
     ffmpeg -i "$f" -ar 16000 -ac 1 \
       "docs/eval/fixtures/$(basename "${f%.*}").wav"
   done
   ```
   檔名要對上你想用的 id(例如 `zh-short-01.wav`)。
4. **寫 `docs/eval/fixtures/manifest.json`**：複製
   `manifest.example.json` 改。每段一筆，`reference` 填你實際講的逐字
   稿，一字不差。`tokenization`：中文填 `character`(算 CER)，英文填
   `word`。
5. **產 baseline**：
   ```bash
   scripts/eval.sh --bootstrap-baseline
   ```
   會寫出 `docs/eval/baseline.json`。把 fixtures + manifest + baseline
   一起 commit 到 `feat/sprint6-wer-eval-harness` 這個 branch。Sprint 6
   變 SHIPPED，可以 push 開 PR。再重新 fire 同一個 `/goal`，它會接著
   跑 Sprint 7(Bug #1)和 Sprint 8，每段都被 `scripts/eval.sh` 把關。

## 注意

- fixture 會 commit 進 repo(16 kHz 單聲道、每段幾秒，很小)，這樣
  baseline 可重現。哪天檔案變大再改用 git-lfs。
- 之後重錄會改變 baseline。只有在「故意換 model 或故意換整組 clip」
  這種有意改動時才跑 `--bootstrap-baseline`，絕不能拿來蓋掉
  regression。
