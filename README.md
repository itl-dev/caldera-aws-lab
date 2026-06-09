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

# 3. 構築（サーバ+やられ役1台）。5〜10分でUIビルド完了
terraform init
terraform apply -auto-approve

# 4. エージェント登録の確認（数分後）。出力されたコマンドを実行
terraform output -raw check_agents | bash
#   => get-command-invocation で StandardOutputContent を見ると登録エージェントが分かる

# 5. UIをブラウザで開く（FW回避：SSMポートフォワード）
terraform output -raw open_ui_via_ssm
#   表示されたコマンドを別タブで実行 → http://localhost:8888 （ログイン: red/admin）

# 6. 片付け（課金停止）
terraform destroy -auto-approve
```

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
| `ui_cidr` | `""` | UIを直接公開したいIP `x.x.x.x/32`（通常は不要・SSM推奨） |
| `rdp_cidr` | `""` | やられ役にRDPを開けたいIP `x.x.x.x/32`（GUIで実画面を見たい時） |
| `disable_realtime_protection` | `false` | Defenderリアルタイム保護も無効化を試みる（Tamper Protectionで弾かれる場合あり） |

例: やられ役を3台、自宅IPからRDP可に:
```bash
terraform apply -auto-approve -var victim_count=3 -var "rdp_cidr=$(curl -s ifconfig.me)/32"
```

---

## アクセス方法（すべて SSM = FWを通る）

```bash
# サーバへキーレスでシェル
terraform output -raw ssm_shell_server | bash

# UIをローカルブラウザで（ポートフォワード）→ http://localhost:8888
terraform output -raw open_ui_via_ssm    # 表示コマンドを実行
```

CALDERA ログイン: **`red` / `admin`**（または `admin`/`admin`）。API キー: `ADMIN123`（`--insecure` で `conf/default.yml` 使用）。

RDP で実画面を見たい場合のみ、`-var "rdp_cidr=<自IP>/32"` で 3389 を開け、
`get-password-data` でパスワードを復号して接続（大学FWが3389を許可している必要あり）。

---

## 仕組み / 設計メモ

- **AMI**: Amazon製 Quick Start（Ubuntu 22.04 / Windows Server 2022 Base）を `data` で自動最新解決。Marketplace AMIはLearner Lab非対応のため不使用。
- **SSM**: `LabInstanceProfile`（=`LabRole`）を両インスタンスに付与。鍵もRDPも使わずシェル/ポートフォワードが可能。
- **サーバ**: `systemd` 常駐（Learner Lab のセッション stop/start 後も自動復帰）。UIは Node 20 でビルド、sandcat は Go でオンデマンドコンパイル（systemdに `HOME`/`GOPATH`/`GOCACHE` を設定済み）。
- **やられ役**: EC2 ユーザーデータ(PowerShell)で Defender 除外 → sandcat を **最大30分リトライ**でDL・常駐。サーバ起動を待たずに済む。

### トラブルシュート
- **エージェントが出てこない**: サーバのUIビルドに時間がかかり、やられ役の30分リトライを超えた場合。
  `terraform apply -replace=aws_instance.victim[0]` でやられ役だけ作り直すと、起動済みサーバへ即コールバックします。
- **UIが開かない**: ビルド完了まで5〜10分。`terraform output -raw ssm_shell_server | bash` でサーバに入り
  `systemctl is-active caldera` / `journalctl -u caldera -f` を確認。

---

## コスト / 注意
- server `t3.large` + victim `t3.medium`。**使い終わったら必ず `terraform destroy`**。
- Learner Lab: us-east-1のみ(`vockey`)、large以下、同時9台/32vCPU、**20台以上で即アカウント停止**。
- このリポジトリにシークレットは含みません（AWS鍵なし。CALDERA既定認証は公知）。
