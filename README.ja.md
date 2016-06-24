Oracle モニタリングテンプレート
===============================

Oracle モニタリング
-------------------

Oracle のパフォーマンスモニタリングや、Oracle 表領域使用率、Oracle アラートログの監視をします(*1)。

その特徴は、以下の通りです。

* Oracle R12 をサポートします。
* HA構成の場合、サービスIPのチェックを行い、稼働系でデータ採取をします。
* ネットワーク経由で複数インスタンスの DB をリモート採取する構成が可能です。
* Oracle パフォーマンス調査用パッケージ Statspack もしくは、 AWR (*2)を使用します。
	- Statspack レベル 5以上で、SQL 負荷ランキンググラフを表示します。
	- Statspack レベル 7以上で、オブジェクトアクセス負荷ランキンググラフを表示します。
* Zabbix を使用して、Oracle の表領域使用率の閾値監視をします(*2)。
* Zabbix と、Zabbix エージェントを使用して、Oracle アラートログの監視をします(*3)。

**注意事項**

1. Zabbix 監視はオプションとなります。
2. AWR を利用する際はオプションライセンスが必要です。詳細は [Oracle社ホームページ](http://www.oracle.com/)を参照してください。
3. Oracle 表領域使用率の閾値監視にはZabbixサーバが必要になります。Oracle アラートログ監視には、Zabbix サーバに加え、監視エージェントが必要になります。

ファイル構成
------------

テンプレートに必要な設定ファイルは以下の通りです。

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

前述で作成した $GETPERF_HOME/var/template/archive/config-Oracle.tar.gz をインポートします。

	cd {モニタリングサイトホーム}
	tar xvf $GETPERF_HOME/var/template/archive/config-Oracle.tar.gz

Cacti グラフテンプレートをインポートします。

	cacti-cli --import Oracle

インポートした集計スクリプトを反映するため、集計デーモンを再起動します

	sumup restart


エージェントセットアップ
========================

HA構成の場合の設定
------------------

サーバで Oracle インスタンスが稼働しているかチェックするスクリプト hastat.pl を編集します。
HA構成のサーバの場合、本スクリプトを実行して稼働系のサーバのみ情報採取をする様に事前チェックを行います。

	vi ~/ptune/script/hastat.pl

サービスIP

	my %services = (
	        '192.168.10.2' => 'orcl',
	);

ネットワーク経由でリモート採取する場合の設定
--------------------------------------------

Statspack/AWR の設定
--------------------

Statspack の場合

AWR の場合

Oracle アラートログの監視設定
-----------------------------

エージェントの起動
------------------

Cacti グラフ登録
================


上記エージェントセットアップ後、データ集計が実行されると、サイトホームディレクトリの node の下にノード定義ファイルが出力されます。
出力されたファイル若しくはディレクトリを指定してcacti-cli を実行します。

	cacti-cli node/Oracle/{Oracleインスタンス名}/

Zabbix 監視登録
===============

その他
======

**注意事項 : Statspack導入の注意点**

Statspack を運用する場合は Statspack データ領域の定期メンテナンスをする必要があります。
メンテナンスをせずに Statspack 運用すると、Statspack のスナップショットの採取負荷影響など思わぬ障害が発生する場合が有ります。
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

AUTHOR
-----------

Minoru Furusawa <minoru.furusawa@toshiba.co.jp>

COPYRIGHT
-----------

Copyright 2014-2016, Minoru Furusawa, Toshiba corporation.

LICENSE
-----------

This program is released under [GNU General Public License, version 2](http://www.gnu.org/licenses/gpl-2.0.html).
