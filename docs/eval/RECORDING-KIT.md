# Murmur Eval 錄音手冊 — v0.1(MacBook only,約 15 分鐘)

> v0.1 = macOS only,所以這版 fixture 全部用 MacBook 麥克風錄。
> iPhone clips 等 v0.2 sprint 開了再加(manifest schema 已經支援,加
> entries 就好,不用改 harness)。

## 你要產出什麼

12 段 MacBook 麥克風錄的 wav + 每段你實際講的逐字稿,放進
`docs/eval/fixtures/`,列在 `docs/eval/fixtures/manifest.json`。

## 錄音清單(12 段,全 MacBook 麥克風)

| id | 語言 | 講什麼 |
|---|---|---|
| zh-short-01..06 | 中文 | 6 句短中文,每句 6 字以內。這就是 Bug #1 出包的地方(短中文被轉成英文) |
| zh-long-01..03 | 中文 | 3 句較長中文,15 到 25 字 |
| en-01..03 | 英文 | 3 句正常長度英文 |

每段內容不同。正常語速,不要刻意放慢。

## 一次性設定

確認有 ffmpeg:

```bash
brew install ffmpeg   # 沒裝才裝
```

列出 MacBook 的 audio input device 編號(只做一次,記下你麥克風的
index,後面要填):

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A1 "AVFoundation audio"
```

輸出長這樣,記下 `MacBook 麥克風`(或 `MacBook Pro Microphone`)前面
那個數字,假設是 `0`:

```
[AVFoundation indev] AVFoundation audio devices:
[AVFoundation indev]  [0] MacBook Pro Microphone
```

下面範例都用 `0`,你不是就換成你的數字。

## 步驟

1. **進 repo**:
   ```bash
   cd /Users/panda/site/apps/murmur
   ```

2. **錄一段**(指令在 terminal 跑,跑了之後馬上對著 MacBook 講,講完
   等它自己停):
   ```bash
   ffmpeg -y -f avfoundation -i ":0" -ar 16000 -ac 1 -t 5 \
     docs/eval/fixtures/zh-short-01.wav
   ```
   - `-t 5` = 錄 5 秒。短中文用 5,長中文 / 英文用 8。
   - `-i ":0"` 的 `0` 換成你剛才查到的 index。
   - 第一次跑 ffmpeg avfoundation 會跳麥克風權限視窗,授權給 Terminal
     (System Settings ▸ Privacy & Security ▸ Microphone)。

3. **照清單錄完 12 段**,id 對到檔名一致:
   ```
   docs/eval/fixtures/zh-short-01.wav   ...   zh-short-06.wav
   docs/eval/fixtures/zh-long-01.wav    ...   zh-long-03.wav
   docs/eval/fixtures/en-01.wav         ...   en-03.wav
   ```
   重錄某段就再跑一次同樣指令會直接蓋掉(`-y`)。

4. **聽一遍確認沒有空檔或爆音**:
   ```bash
   afplay docs/eval/fixtures/zh-short-01.wav
   ```

5. **寫 manifest**:複製 example 改:
   ```bash
   cp docs/eval/fixtures/manifest.example.json docs/eval/fixtures/manifest.json
   ```
   打開 `manifest.json`,12 段每段一筆。`reference` 填你實際講的逐字
   稿,一字不差。`tokenization`:中文填 `character`(算 CER),英文填
   `word`。`source` 全部填 `macbook-mic`。

6. **產 baseline**:
   ```bash
   scripts/eval.sh --bootstrap-baseline
   ```
   會跑 WhisperKit 一次過完 12 段(第一次跑會下載 model,約 140 MB,等
   一下),輸出每段 WER + overall WER,然後寫 `docs/eval/baseline.json`。

7. **commit 上 branch**:
   ```bash
   git add docs/eval/fixtures/ docs/eval/baseline.json
   git commit -m "feat(eval): MacBook-mic fixture set + WER baseline (Sprint 6b)"
   git push -u origin feat/sprint6-wer-eval-harness
   ```
   開 PR。Sprint 6 → SHIPPED。再 fire 同一個 `/goal`,它接著跑 Sprint 7
  (Bug #1) 和 Sprint 8,每段都被 `scripts/eval.sh` 把關。

## 卡住的時候

**`AVFoundation audio devices:` 後面是空的 / 一個 device 都沒列出來**
= 你的 terminal app 沒有麥克風權限。list-devices 不會自動跳權限視窗
(它只查不錄),要手動授權:

1. System Settings ▸ Privacy & Security ▸ Microphone,找你的 terminal
   app 打開開關。
2. 不在清單裡的話,先強制觸發一次權限請求:
   ```bash
   ffmpeg -y -f avfoundation -i ":0" -ar 16000 -ac 1 -t 1 /tmp/perm-probe.wav
   ```
   會跳系統視窗,點允許。
3. **完全關掉 terminal 視窗再開新的**(權限變動對已開的 shell 不即時
   生效)。重跑 list-devices 應該看到 `[0] MacBook Pro Microphone`。

## 注意

- fixtures 直接 commit 進 repo(12 段 × 5 秒 × 16 kHz mono ≈ 2 MB,小)。
  哪天檔案變大再改 git-lfs。
- 只有「故意換 model」或「故意換整組 clip」才再跑
  `--bootstrap-baseline`。絕不能拿它蓋掉 regression。
- iPhone clips 在 v0.2 sprint 開了之後 augment 同一個 manifest +
  baseline,不是現在做。
