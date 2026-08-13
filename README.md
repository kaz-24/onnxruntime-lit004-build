[README.md](https://github.com/user-attachments/files/31013308/README.md)
# onnxruntime-lit004-build# lit004 用 ONNX Runtime GitHub Actions ビルドパック

ロリポップ `lit004` 用のカスタム ONNX Runtime wheel を GitHub Actions で作るためのパックです。

## 対象

- ONNX Runtime: `1.16.3`
- Python: CPython `3.10`
- CPU: `x86_64`
- Linux ABI: `manylinux2014` / glibc `2.17+`
- `onnxruntime_ENABLE_CPUINFO=OFF`
- GPU/CUDAなし

lit004 では標準 ONNX Runtime が `/proc/cpuinfo` の解析で落ちたため、cpuinfo をビルド時に無効化します。

## GitHubでの使い方

1. GitHubで空のリポジトリを1個作成します。
2. このZIPを展開し、中身をリポジトリのルートへアップロードします。
3. GitHubの `Actions` を開きます。
4. `Build ONNX Runtime for lit004` を選択します。
5. `Run workflow` を押します。
6. ビルドが緑色になったら、その実行画面下部の `Artifacts` を開きます。
7. `onnxruntime-1.16.3-lit004-cp310-manylinux2014-cpuinfo-off` をダウンロードします。

Artifactには次が入ります。

- カスタム `onnxruntime-1.16.3-...manylinux2014_x86_64.whl`
- `build-info.txt`
- `test-output.txt`

`test-output.txt` の最後が次ならGitHub側テスト成功です。

```text
RESULT: PASS
```

## lit004へ入れる

標準の `onnxruntime-1.16.3` wheel の代わりに、Actionsで生成したカスタムwheelをKDBの

```text
/web/koseki/packages/
```

へFTPでアップロードします。

既存の標準ONNX Runtime wheelは、混同を避けるため `packages/` から削除してください。

その後、KDBの診断ジョブを再作成してcron診断を実行します。

```text
https://kdb.spkakky.com/tools/diag_setup.php
```

状態確認:

```text
https://kdb.spkakky.com/tools/diag_status.php
```

次の確認点は `onnxruntime` import と `InferenceSession` がlit004上で正常に通ることです。

## なぜmanylinux2014か

`manylinux2014_x86_64` はCentOS 7 / glibc 2.17を基準とします。lit004で確認した環境も `x86_64 / glibc 2.17 / CentOS 7` なので、このABIを狙います。

## ビルドが失敗した場合

GitHub Actionsの失敗したステップを開いて、末尾50〜100行程度を確認してください。特に以下を見ます。

- CMake configure failure
- submodule download failure
- compiler error
- `auditwheel repair` failure
- `RESULT: PASS` 前のONNX Runtime初期化エラー

このパックでは `CMakeCache.txt` を確認し、`onnxruntime_ENABLE_CPUINFO=OFF` が実際に反映されていなければビルドを失敗させるようにしています。
