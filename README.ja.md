Nimble Storage モニタリングテンプレート
===============================================

Nimble Storage モニタリング
-------------

以下の監視対象に対して東芝ストレージサポートユーティリティ付属の、tsuacsコマンド(ArrayFort の場合は aeuacs)を
実行してストレージのパフォーマンス情報を採取します。採取したデータをモニタリングサーバ側で集計してグラフ登録をします。


ファイル構成
-------

テンプレートに必要な設定ファイルは以下の通りです。

|           ディレクトリ           |        ファイル名        |                  用途                 |
|----------------------------------|--------------------------|---------------------------------------|
| lib/agent/Oracle/conf/           | iniファイル              | エージェント採取設定ファイル          |
| lib/agent/Oracle/script/         | 採取スクリプト           | エージェント採取スクリプト            |
| lib/Getperf/Command/Site/Oracle/ | pmファイル               | データ集計スクリプト                  |
| lib/graph/Oracle/                | jsonファイル             | グラフテンプレート登録ルール          |
| lib/cacti/template/0.8.8g/       | xmlファイル              | Cactiテンプレートエクスポートファイル |
| script/                          | create_graph_template.sh | グラフテンプレート登録スクリプト      |

Nimble Storage モニタリング仕様
-----------------------

|     監視項目    | 間隔(規定値) |                              定義                             |
|-----------------|--------------|---------------------------------------------------------------|
| Global I/O 統計 | 30秒         | Nimble Storage 用 SNMP 統計(コントローラ用)を採取します       |
| Volume I/O 統計 | 30秒         | Nimble Storage 用 SNMP 統計(ディスクボリューム用)を採取します |

**リファレンス**

* [Nimble OS SNMP Reference Guide](https://static.spiceworks.com/attachments/post/0007/3827/nimble_os_snmp_reference_guide.pdf)

Install
=====

Oracleテンプレートのビルド
-------------------

Git Hub からプロジェクトをクローンします

	(git clone してプロジェクト複製)

プロジェクトディレクトリに移動して、--template オプション付きでサイトの初期化をします

	cd t_Nimble
	initsite --template .

Cacti グラフテンプレート作成スクリプトを順に実行します

	./script/create_graph_template.sh

Cacti グラフテンプレートをファイルにエクスポートします

	cacti-cli --export Nimble

集計スクリプト、グラフ登録ルール、Cactiグラフテンプレートエクスポートファイル一式をアーカイブします

	mkdir -p $GETPERF_HOME/var/template/archive/
	sumup --export=Nimble --archive=$GETPERF_HOME/var/template/archive/config-Nimble.tar.gz

Nimbleテンプレートのインポート
---------------------

前述で作成した $GETPERF_HOME/var/template/archive/config-Nimble.tar.gz がNimbleテンプレートのアーカイブとなり、
監視サイト上で以下のコマンドを用いてインポートします

	cd {モニタリングサイトホーム}
	tar xvf $GETPERF_HOME/var/template/archive/config-Nimble.tar.gz

Cacti グラフテンプレートをインポートします。

	cacti-cli --import Nimble

インポートした集計スクリプトを反映するため、集計デーモンを再起動します

	sumup restart

使用方法
=====

Statspack の導入
--------------------

Statspack レポートは定期的に DB 統計情報をスナップショット表に蓄積するため、定期的にスナップショット表をメンテナンスする必要があります。
メンテナンスをせずに Statspack 運用すると、Statspackのスナップショットの採取負荷影響など思わぬ障害が発生する場合が有ります。
以下の点を心がけ、計画的に Statspack を導入するようにしてください。

1. Statspack 用表領域の作成
2. Statspack パッケージインストール
3. Statspack スナップショット統計情報採取の定期実行
4. Statspack 閾値の定期調整

AWR レポートを使用する場合は上記作業は不要です。

|       スクリプト        |                    内容                    |
|-------------------------|--------------------------------------------|
| ora_sp_run_stat.sh      | スナップショット表の統計情報を採取します   |
| ora_sp_tuning_param.sql | Statspack 閾値調整用にサイズの調整をします |
|                         |                                            |

エージェントセットアップ
--------------------

ArrayFort の場合、以下のエージェント採取設定ファイルを監視対象サーバにコピーして、エージェントを再起動してください。

	{サイトホーム}/lib/agent/Oracle/conf/Oracle.ini

script/hastat.pl スクリプトの編集



SC3000 の場合、監視対象サーバから直接採取する場合と、リモートで採取する場合で実行オプションの変更が必要になります。

	vi {サイトホーム}/lib/agent/Oracle/conf/SC3000.ini

以下例はリモート採取の設定となります。

	;---------- Monitor command config (Storage HW resource) -----------------------------------
	STAT_ENABLE.Oracle = true
	STAT_INTERVAL.Oracle = 300
	STAT_TIMEOUT.Oracle = 400
	STAT_MODE.Oracle = concurrent

	; SC3000
	STAT_CMD.Oracle = 'sudo /usr/local/TSBtsu/bin/tsuacs -h {ストレージIPアドレス} -T 60 -n 5 -all',   {ストレージIPアドレス}/tsuacs.txt

データ集計のカスタマイズ
--------------------

上記エージェントセットアップ後、データ集計が実行されると、サイトホームディレクトリの lib/Getperf/Command/Master/ の下に Oracle.pm ファイルが出力されます。
本ファイルは監視対象ストレージのマスター定義ファイルで、ストレージのコントローラ、LUN、Raidグループの用途を記述します。
同ディレクトリ下の Oracle.pm_sample を例にカスタマイズしてください。

グラフ登録
-----------------

上記エージェントセットアップ後、データ集計が実行されると、サイトホームディレクトリの node の下にノード定義ファイルが出力されます。
出力されたファイル若しくはディレクトリを指定してcacti-cli を実行します。

	cacti-cli node/ArrayFort/{ストレージノード}/

AUTHOR
-----------

Minoru Furusawa <minoru.furusawa@toshiba.co.jp>

COPYRIGHT
-----------

Copyright 2014-2016, Minoru Furusawa, Toshiba corporation.

LICENSE
-----------

This program is released under [GNU General Public License, version 2](http://www.gnu.org/licenses/gpl-2.0.html).
