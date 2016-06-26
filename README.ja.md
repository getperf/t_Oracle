Oracle モニタリングテンプレート
===============================

Oracle モニタリング
-------------------

Oracle のパフォーマンス統計、Oracle 表領域使用率、Oracle アラートログの監視をします。

* Oracle R12 をサポートします。
* データ採取時にサービスIPのチェックを行い、HA構成の稼働系に対してデータ採取をします。
* 複数サーバ、複数インスタンスの DB の場合、1つのエージェントから SQL*Net 経由で複数DBのデータを採取します。
* Oracle パフォーマンス調査用パッケージ Statspack もしくは、 AWR (*1) を使用します。
	- Statspack レベル 5以上で、SQL ランキンググラフを表示します。
	- Statspack レベル 7以上で、オブジェクトアクセスランキンググラフを表示します。
* Zabbix を使用して、Oracle の表領域使用率の閾値監視をします(*2)。
* Zabbix と、Zabbix エージェントを使用して、Oracle アラートログ監視をします(*2)。

**注意事項**

1. Statspack は事前にインストールする必要があります。AWR を利用する際は特定のライセンスが必要になります。詳細は [Oracle社ホームページ](http://www.oracle.com/technetwork/jp/articles/index-349908-ja.html)　を参照してください。
2. Zabbix 監視はオプションで、 Oracle 表領域使用率の閾値監視には Zabbix サーバが必要になります。Oracle アラートログ監視には、Zabbix サーバに加え、Zabbix エージェントが必要になります。

ファイル構成
------------

テンプレートのファイル構成は以下の通りです。

|           ディレクトリ           |        ファイル名        |                  用途                 |
|----------------------------------|--------------------------|---------------------------------------|
| lib/agent/Oracle/conf/           | iniファイル              | エージェント採取設定ファイル          |
| lib/agent/Oracle/script/         | 採取スクリプト           | エージェント採取スクリプト            |
| lib/Getperf/Command/Site/Oracle/ | pmファイル               | データ集計スクリプト                  |
| lib/graph/Oracle/                | jsonファイル             | グラフテンプレート登録ルール          |
| lib/cacti/template/0.8.8g/       | xmlファイル              | Cactiテンプレートエクスポートファイル |
| script/                          | create_graph_template.sh | グラフテンプレート登録スクリプト      |


Install
=======

テンプレートのビルド
--------------------

Git Hub からプロジェクトをクローンします。

	(git clone してプロジェクト複製)

プロジェクトディレクトリに移動して、--template オプション付きでサイトの初期化をします。

	cd t_Oracle
	initsite --template .

Cacti グラフテンプレート作成スクリプトを順に実行します。

	./script/create_graph_template__oracle.sh

Cacti グラフテンプレートをファイルにエクスポートします。

	cacti-cli --export Oracle

集計スクリプト、グラフ登録ルール、Cactiグラフテンプレートエクスポートファイル一式をアーカイブします。

	mkdir -p $GETPERF_HOME/var/template/archive/
	sumup --export=Oracle --archive=$GETPERF_HOME/var/template/archive/config-Oracle.tar.gz

テンプレートのインポート
------------------------

監視サイトに前述で作成したアーカイブファイルを解凍します。

	cd {モニタリングサイトホーム}
	tar xvf $GETPERF_HOME/var/template/archive/config-Oracle.tar.gz

Cacti グラフテンプレートをインポートします。

	cacti-cli --import Oracle

インポートした集計スクリプトを反映するため、集計デーモンを再起動します。

	sumup restart


エージェントセットアップ
========================

データ採取スクリプトの配布
--------------------

Oracleデータ採取ライブラリ一式を、監視対象のOracleサーバに配布します。監視サイトのlib の下にある以下のディレクトリ下のファイル一式を監視対象の エージェントホームディレクトリにコピーします。

	ls lib/agent/Oracle/
	conf  script

エージェントホームディレクトリにコピーします。

	scp lib/agent/Oracle/* {OSユーザ}@{監視対象IP}:~/ptune/

エージェント実行 OSユーザの環境設定
------------------------

ここからの作業は監視対象のエージェントが稼働するサーバで行います。
エージェント実行 OSユーザに sqlplus などのコマンドが実行できるよう、Oracle の環境変数の設定を行います。
以下のOracle ホームの環境変数設定ファイルをコピーします。

	sudo ls -la ~oracle/.profile_orcl
	-rwxrwxr-x 1 oracle oinstall 2091  5月 20 06:20 2016 /home/oracle/.profile_orcl

環境変数設定ファイルをエージェントホームディレクトリ下の以下のパスにコピーし、参照権限を付与します。

	sudo cp ~oracle/.profile_orcl ~/ptune/script/ora12c/oracle_env
	sudo chmod a+r ~/ptune/script/ora12c/oracle_env

コピーした環境変数設定ファイルを読み込んで、エージェント実行OSユーザで sqlplus で接続できるか動作確認をします。

	source ~/ptune/script/ora12c/oracle_env
	sqlplus perfstat/perfstat

接続できたら、'quit'でsqlplusを終了します。

HA構成の場合の設定
------------------

HA構成のサーバの場合、稼働系のサーバのみでデータ採取を実行する様に事前チェックを行う設定が必要です。チェックスクリプト hastat.pl を編集します。

	vi ~/ptune/script/hastat.pl

以下例のように 監視対象の Oracle インスタンスとサービス IP の紐づけを設定します。

	my %services = (
	        '192.168.0.1' => 'orcl',
	);

Statspack/AWR の設定
--------------------

エージェントホームディレクトリ下の、conf/Oracle.ini 設定ファイルを編集して、Statspack または、 AWR のデータ採取スクリプトの実行オプションを設定します。

**注意事項**

設定ファイル Oracle.ini のデフォルトは Statspack が有効になっており、AWR の設定はコメントアウトしています。
後述の AWR を使用する場合は、Statspack の設定をコメントアウトして、AWR の設定を有効にしてください。

**Statspack の場合**

Oracle.ini ファイルの以下の行を編集します。

	; Performance report for Statspack
	STAT_CMD.Oracle = '_script_/sprep.sh ...'

行内の sprep.sh スクリプトで Statspack のデータ採取を行います。その実行オプションは以下の通りです。

	sprep.sh [-s] [-n purgecnt] [-u user/pass[@tns]] [-i sid]
	           [-l dir] [-r instance_num] [-d ora12c]\n
	           [-v snaplevel] [-e err] [-x]

* -s

	Statspack スナップショットを実行します。

* -n {purgecnt}

	指定した数値の世代数で Statspack スナップショットデータの削除を行います。既定値は0で削除をしません。

* -u {user}/{pass}[@tns]

	Statspack 接続情報を設定します。

* -i {sid}

	Oracleインスタンス名を指定します。

* -l {dir}

	Statspack レポートの保存ディレクトリを指定します。Oracle.ini での設定は \_odir\_ マクロを指定します。

* -r {instance_num}

	Oracle RAC 構成の場合、インスタンス番号を指定します。

* -d {dir}

	{エージェントホーム}/ptune/script の下の、各 Oracle バージョンの SQLディレクトリを指定します。デフォルトは ora12c です。

* -v {snaplevel}

	指定した数値のスナップショットレベルでスナップショットを実行します。

* -e {errorfile}

	エラーログの出力ファイルを指定します。

* -x

	指定すると、HA構成の稼働系のサーバのチェックを行いません。ネットワーク経由でリモート採取する場合に指定します。

**AWR の場合**

Oracle.ini ファイルの以下の行を編集します。

	; Performance report for AWR
	;STAT_CMD.Oracle = '_script_/awrrep.sh -l _odir_ -d ora12c -v 1'
	;STAT_CMD.Oracle = '_script_/chcsv.sh  -l _odir_ -d ora12c -f ora_sql_topa'
	;STAT_CMD.Oracle = '_script_/chcsv.sh  -l _odir_ -d ora12c -f ora_obj_topa'

行内の awrrep.sh スクリプトで AWR レポート採取を行います。
awrrep.sh　の実行オプションは以下となり、値の定義はsprep.sh と同様です。

	awrrep.sh [-u user/pass[@tns]] [-i sid]
	          [-l dir] [-d ora12c] [-v snaplevel] [-e err] [-x]

AWR は Statspack と違い、AWR側でスナップショットの実行や削除をスケジューリングします。
AWR の設定や運用の詳細は[Oracle社ホームページ](https://blogs.oracle.com/oracle4engineer/entry/column_howtouse_awr)を参照してください。

Oracle アラートログの参照権限の付与
-----------------------------

アラート・ログは以下のように初期化パラメータ DIAGNOSTIC_DEST で示される場所に出力されています。

	<DIAGNOSTIC_DEST>/diag/rdbms/<DB_NAME>/<SID>/trace/

DIAGNOSTIC_DEST のデフォルトの設定は ORACLE_BASE 環境変数ですので、例えば ORACLE_BASE 環境変数が "/u01/app/oracle" でかつデータベース名、SID が "orcl" の場合、アラート・ログの出力先は、以下となります。

	sudo ls -l /u01/app/oracle/diag/rdbms/orcl/orcl/trace/alert_orcl.log
	-rw------- 1 oracle oinstall 207816  6月 26 09:05 2016 /u01/app/oracle/diag/rdbms/orcl/orcl/trace/alert_orcl.log

オーナのみのアクセス権限となっているため、エージェント実行ユーザがアクセスできるよう、参照権限を付与します。

	sudo chmod a+r /u01/app/oracle/diag/rdbms/orcl/orcl/trace/alert_orcl.log

エージェント実行ユーザでアクセスができるか確認します。

	tail /u01/app/oracle/diag/rdbms/orcl/orcl/trace/alert_orcl.log

エージェントの起動
------------------

設定を反映させるため、エージェントを再起動します。

	~/ptune/bin/getperfctl stop
	~/ptune/bin/getperfctl start

Cacti グラフ登録
================

上記エージェントセットアップ後、データ集計が実行されると、サイトホームディレクトリの node の下にノード定義ファイルが出力されます。
出力されたノード定義ディレクトリを指定して cacti-cli を実行します。

	cd {サイトホーム}
	cacti-cli node/Oracle/{Oracleインスタンス名}/

Zabbix 監視登録
===============

.hosts への監視対象サーバIPの登録
----------------------------

監視対象サーバのDNSなどが設定されていない場合は、.hosts ファイルに IP アドレスの設定をします。

	cd {サイトホーム}
	vi .hosts

"IPアドレス ホスト名" の形式で IP　アドレスを登録してください。

Zabbix の監視設定
--------------------

zabbix-cli コマンドの、 --info オプションで設定内容の確認をしてから、--add オプションで登録します。

**表領域閾値監視の設定**

	# 設定内容の確認
	zabbix-cli --info node/Oracle/{Oracleインスタンス名}/
	# 問題がなければ登録
	zabbix-cli --add node/Oracle/{Oracleインスタンス名}/

**Oracleアラートログの監視設定**

	# 設定内容の確認
	zabbix-cli --info node/Linux/{監視対象サーバ}/
	# 問題がなければ登録
	zabbix-cli --add node/Linux/{監視対象サーバ}/

その他
======

**Statspack導入の注意点**

Statspack を運用する場合は Statspack データ領域の定期メンテナンスをする必要があります。
メンテナンスを怠ると、Statspack 実行時の負荷影響などで思わぬ障害が発生する場合が有ります。
以下の点を心がけ、計画的に Statspack を導入するようにしてください。

1. Statspack 専用表領域リソースの確保
2. Statspack スナップショット用 統計情報の定期採取
4. Statspack スナップショット閾値の定期調整

Statspack メンテナンス用に ptune/script の下に以下のスクリプトを用意しています。

|       スクリプト        |                    内容                    |
|-------------------------|--------------------------------------------|
| ora_sp_run_stat.sh      | スナップショット表の統計情報を採取します   |
| ora_sp_tuning_param.sql | Statspack 閾値調整用のレポートをします |

AUTHOR
-----------

Minoru Furusawa <minoru.furusawa@toshiba.co.jp>

COPYRIGHT
-----------

Copyright 2014-2016, Minoru Furusawa, Toshiba corporation.

LICENSE
-----------

This program is released under [GNU General Public License, version 2](http://www.gnu.org/licenses/gpl-2.0.html).
