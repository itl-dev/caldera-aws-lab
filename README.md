# caldera-aws-lab

AWS Academy **Learner Lab** 上に、**MITRE CALDERA サーバ**と**やられ役 Windows**（sandcat エージェント常駐）を
**Terraform 一発**で立てる演習用 IaC。`terraform apply` だけで以下が自動構築されます。

```
[CALDERA server (Ubuntu)] <--8888(VPC内)-- [Windows victim x N]
        ↑ UIはSSMで安全に閲覧                  └ 起動時にsandcatをDL・常駐しCALDERAへ自動登録
```

- 鍵は `vockey` 既定、Defender 除外も起動時に自動適用、エージェント配置までフルオート
- やられ役は **サーバの private IP を自動参照**（IPの手貼り不要）
- UI/シェルは **AWS Systems Manager (SSM)** 経由 = **大学等の厳しいファイアウォール(8888/22/3389遮断)でも到達可能**（HTTPS 443のみ）

---

## 受講生向けクイックスタート（CloudShell）

> マネジメントコンソール右上の**リージョンを `us-east-1`** にしてから CloudShell を開く。
> CloudShell は認証情報がプリセット済み・`session-manager-plugin` 導入済み。

```bash
# 1. 取得
git clone https://github.com/itl-dev/caldera-aws-lab.git
cd caldera-aws-lab

# 2. CloudShell 準備（Terraform導入 + 共有プラグインキャッシュ）。source で実行すること
source ./setup.sh

# 3. 構築。UIを手元ブラウザで見るため、自分のグローバルIPに 443 を開ける
#    ★IPは「手元ブラウザで https://ifconfig.me を開いて」確認する
#     （CloudShell の curl ifconfig.me は CloudShell のIPになるので使わない）
terraform init
terraform apply -auto-approve -var "ui_cidr=<手元のグローバルIP>/32"
#    手早く試すだけなら -var "ui_cidr=0.0.0.0/0"（全公開・要注意。CALDERAはログインあり）

# 4. UIのURLを取得 → 手元ブラウザで開く（自己署名の証明書警告は「許可して進む」。ログイン red/admin）
terraform output -raw ui_url
#    ※UIビルドに5〜10分。直後は 502/未応答 のことがあるので少し待つ

# 5. エージェント登録の確認（数分後）
terraform output -raw check_agents | bash
#    => get-command-invocation で StandardOutputContent を見ると登録エージェントが分かる

# 6. 片付け（課金停止）
terraform destroy -auto-approve
```

> ✅ **UIは手元ブラウザだけで開けます**（aws CLI 等のローカルインストール不要）。サーバ上の Caddy が
> `443/HTTPS → CALDERA(8888)` を中継するので、大学等が 443 しか通さないFWでもアクセスできます。
> 自己署名証明書のため初回だけブラウザ警告が出ます（infosec 的にはむしろ教材）。

> ⚠️ CloudShell の `/home` 永続領域は **1GB**。`setup.sh` が設定する共有プラグインキャッシュ
> (`TF_PLUGIN_CACHE_DIR`) を使わないと AWS provider の重複DLで容量超過します。必ず `source ./setup.sh` を。

---

## よく使う変数

| 変数 | 既定 | 説明 |
|---|---|---|
| `victim_count` | `1` | やられ役の台数（Learner Lab は同時 **9台/32vCPU** 上限） |
| `victim_instance_type` | `t3.medium` | やられ役サイズ（large まで） |
| `server_instance_type` | `t3.large` | サーバサイズ |
| `agent_group` | `red` | CALDERA 上のエージェントグループ名 |
| `ui_cidr` | `""` | UI(HTTPS/443)を開けるIP `x.x.x.x/32`。手元ブラウザのグローバルIP、または `0.0.0.0/0`。空=非公開(SSM運用) |
| `rdp_cidr` | `""` | やられ役にRDPを開けたいIP `x.x.x.x/32`（GUIで実画面を見たい時） |
| `disable_realtime_protection` | `false` | Defenderリアルタイム保護も無効化を試みる（Tamper Protectionで弾かれる場合あり） |

例: やられ役を3台、自宅IPからRDP可に:
```bash
terraform apply -auto-approve -var victim_count=3 -var "rdp_cidr=$(curl -s ifconfig.me)/32"
```

---

## UIをブラウザで開く（受講生向け・ローカルインストール不要）

サーバ上の **Caddy** が `443/HTTPS → CALDERA(8888)` を中継しています。`ui_cidr` で自分のIPに 443 を開ければ、
**手元ブラウザで直接アクセスできます**（aws CLI も session-manager-plugin も不要）。大学FWが 443 を通す限り到達可能。

```bash
# CloudShell で（apply 時に ui_cidr を渡していれば、あとはURLを開くだけ）
terraform output -raw ui_url
#  => https://<server_public_ip>  を手元ブラウザで開く
```
- ログイン: **`red` / `admin`**（または `admin`/`admin`）
- 初回は**自己署名証明書の警告**が出る → 「詳細設定 → アクセスする」で進む
- IPはサーバ stop/start で変わるので、その都度 `terraform output -raw ui_url` で確認
- 自分のグローバルIPは**手元ブラウザで** https://ifconfig.me を開いて確認（CloudShellのcurlは不可）

> 証明書警告も出したくない場合は、`<public-ip>.sslip.io` + Let's Encrypt で無警告TLSにできます（要 80/443 開放）。
> 現状は外部依存のない自己署名を既定にしています。

## UIを非公開のまま見る（教員向け・SSMポートフォワード）

公開したくない（`ui_cidr` を開けたくない）ときは、**手元PC**から SSM ポートフォワードで見られます。
※この方法は手元PCに aws CLI + session-manager-plugin + Learner Lab 認証が必要（受講生配布には不向き）。
※CloudShell 内で張っても手元ブラウザからは見えない（CloudShellの localhost は別物）ので、必ず手元PCで実行。

```bash
aws ssm start-session --target <server_instance_id> --region us-east-1 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
# 張ったまま手元ブラウザで http://localhost:8888
```

## サーバへキーレスでシェル

```bash
terraform output -raw ssm_shell_server | bash    # CloudShell で実行可（SSM=443）
```

API キー: `ADMIN123`（`--insecure` で `conf/default.yml` 使用）。
RDP で実画面を見たい場合のみ `-var "rdp_cidr=<自IP>/32"` で 3389 を開け、`get-password-data` で復号して接続（FWが3389を通す必要あり）。

---

## 仕組み / 設計メモ

- **AMI**: Amazon製 Quick Start（Ubuntu 22.04 / Windows Server 2022 Base）を `data` で自動最新解決。Marketplace AMIはLearner Lab非対応のため不使用。
- **SSM**: `LabInstanceProfile`（=`LabRole`）を両インスタンスに付与。鍵もRDPも使わずシェル/ポートフォワードが可能。
- **サーバ**: `systemd` 常駐（Learner Lab のセッション stop/start 後も自動復帰）。UIは Node 20 でビルド、sandcat は Go でオンデマンドコンパイル（systemdに `HOME`/`GOPATH`/`GOCACHE` を設定済み）。Go は **公式tarballの最新安定版**を導入（CALDERAは go>=1.19 が必須で、Ubuntu apt の 1.18.1 だと要件不足でコンパイルが不安定になるため）。
- **UI公開**: `Caddy` が `443/HTTPS → 8888` を中継。**起動時に公開IPをSANに含む自己署名証明書を生成**し Caddy へ直接渡す（`tls internal` はホスト名なし `:443` だとIP宛て接続に証明書を提示できずTLS失敗するため不使用）。受講生はブラウザのみでアクセス可（443を通すFWで到達、初回だけ証明書警告→許可して進む）。`ui_cidr` でアクセス元を制限。
- **やられ役**: EC2 ユーザーデータ(PowerShell)で Defender 除外 → sandcat を **最大60分リトライ**でDL・常駐。受け取ったバイナリが正規のWindows実行ファイル(MZヘッダ)で、起動後もプロセスが生きていることを確認できるまでリトライするので、サーバ準備に時間がかかっても確実に登録される。

### トラブルシュート
- **エージェントが出てこない**: 通常は60分リトライ内に自動登録される。それでも出ない場合は
  `terraform apply -replace=aws_instance.victim[0]` でやられ役だけ作り直すと、起動済みサーバへ即コールバックします（その際、最初の apply と同じ `-var "ui_cidr=..."` を必ず付け直すこと。省くとUIの443ルールが消える）。
- **UIが開かない**: ビルド完了まで5〜10分。`terraform output -raw ssm_shell_server | bash` でサーバに入り
  `systemctl is-active caldera` / `journalctl -u caldera -f` を確認。

---

## コスト / 注意
- server `t3.large` + victim `t3.medium`。**使い終わったら必ず `terraform destroy`**。
- Learner Lab: us-east-1のみ(`vockey`)、large以下、同時9台/32vCPU、**20台以上で即アカウント停止**。
- このリポジトリにシークレットは含みません（AWS鍵なし。CALDERA既定認証は公知）。
