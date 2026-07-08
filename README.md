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
| `enable_guacamole` | `true` | サーバに Apache Guacamole を入れ、`https://<server>/guac/` で**やられ役のデスクトップをブラウザRDP**（クライアント/鍵/3389開放すべて不要）。`ui_cidr` の443経由 |
| `enable_emu` | `true` | **emu プラグインを起動時に有効化**（CTID Adversary Emulation Library を全clone＋ペイロード取得し、`- emu` を有効化してから初回起動）。`terraform apply` 一発で **FIN6 が使える状態**で立ち上がる。`false` で stockpile のみ（Super Spy 用） |
| `rdp_cidr` | `""` | やられ役に**直接**RDP(3389)を開けたいIP `x.x.x.x/32`（FWが3389を通す環境向け。通常は Guacamole で十分） |
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
- IPはサーバ stop/start で変わる。**`terraform output` は state を読むだけで自動更新されない**ので、再開時はまず `terraform apply`（後述の「ラボを再開する」）で state を更新してから `terraform output -raw ui_url` を見る
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
eval "$(terraform output -raw ssm_shell_server)"   # CloudShell で実行可（SSM=443）
```

> ⚠️ 対話型セッションなので **`eval` を使う**こと。`... | bash` はサブシェルの stdin がパイプになり
> `Cannot perform start session: EOF` で即切断される。

API キー: `ADMIN123`（`--insecure` で `conf/default.yml` 使用）。

## やられ役のデスクトップをブラウザで見る（Guacamole・受講生向け）

`enable_guacamole=true`（既定）なら、**手元ブラウザだけ**でやられ役のWindowsデスクトップを操作できます。
サーバ上の Apache Guacamole が 443(SSM不要・Caddy経由)で配信し、guacd が VPC内部からRDPします。
**RDPクライアントも鍵も3389開放も不要**——大学等が 443 しか通さないFWでも到達できます。

```bash
# UIと同じく ui_cidr が開いていること（apply 時に渡す）。
# enable_guacamole=true のとき、apply 後に URL・ユーザ・パスがまとめて表示される:
terraform output guacamole
#   URL : https://<server_public_ip>/guac/   (accept the self-signed cert warning)
#   User: student
#   Pass: <自動生成パスワード>
# 個別に取りたい場合:
terraform output -raw guacamole_url       # => https://<server_public_ip>/guac/
terraform output -raw guacamole_login     # => student / <自動生成パスワード>
```
- ブラウザで `/guac/` を開く → `student` と上記パスワードでログイン → 接続先 **`caldera-victim-1`** を選ぶ → デスクトップ表示
- やられ役の Administrator パスワードは自動生成（直接RDPやデスクトップ操作用に `terraform output -raw victim_admin_password` で確認可）
- やられ役を増減/作り直しても、サーバが定期的に発見して接続一覧を自動更新（再applyは不要）

> FWが 3389 を通す環境で**直接**RDPしたい場合のみ `-var "rdp_cidr=<自IP>/32"` で 3389 を開け、
> `get-password-data`（vockey鍵）か上記 `victim_admin_password` で接続。通常は Guacamole の方が手軽。

---

## ラボを再開する（Learner Lab を停止→再開したとき）

Learner Lab はセッション終了でインスタンスが **stop** され、次回 **start** で起動します。`destroy` していなければ作り直し不要で、以下だけで再開できます。

```bash
# 1. Learner Lab セッションを Start したあと、CloudShell で:
cd caldera-aws-lab
terraform apply -var "ui_cidr=0.0.0.0/0"   # 変わった public IP を state に反映（再作成はされない）。ui_cidr は必ず付け直す
terraform output -raw ui_url                # 新しい IP の UI を開く
```

- **サーバ**: `systemd` 常駐なので CALDERA / Caddy / Guacamole は自動で復帰。変わるのは public IP だけ（上記 apply で output が更新される）。
- **やられ役のエージェント**: 起動時に自動再接続する **AtStartup スケジュールタスク（`sandcat`）** を仕込んであるので、victim が起動すれば数分で CALDERA に再登録される（サーバの **private IP は stop/start で不変**なので接続先は有効なまま）。
  - もし自動で出てこない場合（または旧版で作った=スケジュールタスクが無い victim）は、1コマンドで再起動:
    ```bash
    terraform output -raw restart_agent | bash   # 全 victim の sandcat を起動（既に動いていればスキップ）
    ```
- 注意: `terraform apply` ではなく `terraform output` だけ見ると **古い IP のまま**なので必ず apply を先に。

## やられ役にエージェントを手動デプロイする（受講生向け）

自動デプロイに頼らず、受講生自身に配備させたいとき（演習として／自動登録が落ちたときの復旧）。**Guacamole で入って PowerShell に貼るだけ**。

1. `https://<server>/guac/` でやられ役のデスクトップを開く（[Guacamole の節](#やられ役のデスクトップをブラウザで見るguacamole受講生向け)）。
2. スタート → `PowerShell` を起動。
3. **CALDERA UI 上で** `agents` → `Deploy an agent` → `Sandcat`／`windows` を選び、表示された PowerShell コマンドをコピーして貼り付け、Enter。

> このコマンドの接続先（`$server`）は CALDERA の `app.contact.http` から生成されます。本リポジトリではサーバ起動時に **`app.contact.http` をサーバの private IP に自動設定**するので、UI が出すコマンドはそのまま動きます（既定の `http://0.0.0.0:8888` は宛先として無効で、IP を手で直す必要があった）。
>
> victim → サーバ 8888 は **VPC 内部のみ許可**なので、接続先は必ず **private IP**（public IP や 0.0.0.0 は不可）。private IP は stop/start で不変なので、コマンドはセッションを跨いで使い回せます。

---

## emu プラグイン（実在APTの再現）を手動で有効化・復旧する【発展】

> **通常は不要**。`enable_emu=true`（既定）なら **ビルド時に自動で有効化**され、`terraform apply`
> 一発で **FIN6 が使える状態**で立ち上がる（[変数表](#よく使う変数)・`userdata-server.sh` 参照）。
> 以下は、**自動有効化が失敗したとき**（ライブラリ clone が途中で切れた等）や、**この自動化より前に
> 作った古いサーバ**を後付けで有効化する**手動・復旧手順**。詳細な演習手順はコース教材
> `演習手順_CALDERA体験_emu_FIN6.md` を参照。

`emu` プラグイン本体は `git clone --recursive` で同梱済み（`/opt/caldera/plugins/emu`）。手動で有効化
する場合は3つのハマりどころがあるので、**必ず下の順序**で行う（自動化 `userdata-server.sh` と同じ処理）。

```bash
eval "$(terraform output -raw ssm_shell_server)"   # サーバへ（対話型なので | bash は不可）
sudo -i && cd /opt/caldera

# 1) ★先に停止する。CALDERA は設定をファイルに書き戻すため、稼働中に default.yml を編集して
#    restart すると停止時に旧設定で上書きされ、追記した「- emu」が消える。
systemctl stop caldera

# 2) plugins に「- emu」を追記。★既存項目と同じインデントで揃える（段がズレると YAML が壊れる）。
#    既存の「- stockpile」行のインデントを複製すれば確実・冪等。
grep -qE '^[[:space:]]*-[[:space:]]*emu[[:space:]]*$' conf/default.yml \
  || sed -i 's/^\([[:space:]]*\)-[[:space:]]*stockpile[[:space:]]*$/\1- stockpile\n\1- emu/' conf/default.yml
venv/bin/python3 -c "import yaml;d=yaml.safe_load(open('conf/default.yml'));assert 'emu' in d['plugins']"

# 3) ★CTID ライブラリは「明示的に」フル clone する。emu の自動取得は
#    「data/adversary-emulation-plans が存在し空でなければ clone をスキップ」する仕様で、
#    自動取得が途中で切れると一部プラン（例: turla のみ）だけ残り FIN6 が生成されず件数0になる。
rm -rf plugins/emu/data/adversary-emulation-plans
git clone --depth 1 \
  https://github.com/center-for-threat-informed-defense/adversary_emulation_library \
  plugins/emu/data/adversary-emulation-plans
ls plugins/emu/data/adversary-emulation-plans/fin6/Emulation_Plan/yaml/   # 取得確認

# 4) 起動 → 各プランの */Emulation_Plan/yaml/*.yaml から abilities/adversaries を生成
systemctl start caldera
```

- 起動後、UI の **plugins → emu** の abilities/adversaries 件数が **0でなくなり**、**adversaries に FIN6**
  が現れれば成功。
- **実ツール本体（payload）**は別途 `plugins/emu/download_payloads.sh` で取得（一部は配布元消滅で 404＝既知）。
- 注意: emu の有効化は**サーバ上のランタイム状態**（`default.yml` 編集＋ライブラリ取得）なので、
  `terraform destroy`／作り直しで消える。作り直したら本節を再実行する。

## 仕組み / 設計メモ

- **AMI**: Amazon製 Quick Start（Ubuntu 22.04 / Windows Server 2022 Base）を `data` で自動最新解決。Marketplace AMIはLearner Lab非対応のため不使用。
- **SSM**: `LabInstanceProfile`（=`LabRole`）を両インスタンスに付与。鍵もRDPも使わずシェル/ポートフォワードが可能。
- **サーバ**: `systemd` 常駐（Learner Lab のセッション stop/start 後も自動復帰）。UIは Node 20 でビルド、sandcat は Go でオンデマンドコンパイル（systemdに `HOME`/`GOPATH`/`GOCACHE` を設定済み）。Go は **公式tarballの最新安定版**を導入（CALDERAは go>=1.19 が必須で、Ubuntu apt の 1.18.1 だと要件不足でコンパイルが不安定になるため）。
- **UI公開**: `Caddy` が `443/HTTPS → 8888` を中継。**起動時に公開IPをSANに含む自己署名証明書を生成**し Caddy へ直接渡す（`tls internal` はホスト名なし `:443` だとIP宛て接続に証明書を提示できずTLS失敗するため不使用）。受講生はブラウザのみでアクセス可（443を通すFWで到達、初回だけ証明書警告→許可して進む）。`ui_cidr` でアクセス元を制限。
- **やられ役**: EC2 ユーザーデータ(PowerShell)で Defender 除外 → sandcat を **最大60分リトライ**でDL・常駐。受け取ったバイナリが正規のWindows実行ファイル(MZヘッダ)で、起動後もプロセスが生きていることを確認できるまでリトライするので、サーバ準備に時間がかかっても確実に登録される。起動時に Administrator パスワード（Terraform `random_password` で自動生成）を設定し、RDPを有効化＋NLA無効化（Mac/Guacamoleの局所アカウントRDPがCredSSPで弾かれるのを回避）。
- **ブラウザRDP(Guacamole)**: サーバの `guacd`＋`tomcat9`＋Guacamole(1.3.0) を Caddy が `/guac` で443公開。接続先(`user-mapping.xml`)は、サーバの `LabRole` で `ec2:DescribeInstances` して**走行中のやられ役を発見**し systemd timer で自動生成（やられ役SGはVPC内部からの3389のみ許可＝非公開）。秘密はリポジトリに持たず `random_password` を両インスタンスへ注入。

### トラブルシュート
- **エージェントが出てこない**: 通常は60分リトライ内に自動登録される。それでも出ない場合は
  `terraform apply -replace=aws_instance.victim[0]` でやられ役だけ作り直すと、起動済みサーバへ即コールバックします（その際、最初の apply と同じ `-var "ui_cidr=..."` を必ず付け直すこと。省くとUIの443ルールが消える）。
- **UIが開かない**: ビルド完了まで5〜10分。`eval "$(terraform output -raw ssm_shell_server)"` でサーバに入り
  `systemctl is-active caldera` / `journalctl -u caldera -f` を確認。
- **Guacamoleで接続先が出ない/つながらない**: サーバのUIビルドに続けて guac 一式の導入に数分かかる。`journalctl -u guacd -f`、`systemctl status tomcat9 guac-sync.timer`、`cat /etc/guacamole/user-mapping.xml` を確認。やられ役を作り直した直後はタイマー(最大2分)での再発見待ち。

---

## コスト / 注意
- server `t3.large` + victim `t3.medium`。**使い終わったら必ず `terraform destroy`**。
- Learner Lab: us-east-1のみ(`vockey`)、large以下、同時9台/32vCPU、**20台以上で即アカウント停止**。
- このリポジトリにシークレットは含みません（AWS鍵なし。CALDERA既定認証は公知）。
