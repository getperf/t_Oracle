Oracle RAC AWRモニタリングテンプレート
======================================

Oracle RAC AWRモニタリング
--------------------------

RAC 用 Oracle AWR レポートを用いてOracleのパフォーマンス統計のモニタリングをします。

**注意事項**

* 従来のOracle AWR 監視設定の RAC版拡張用になります。RAC 版 AWR 採取スクリプト awrgrpt.sql を使用します。

ファイル構成
------------

テンプレートのファイル構成は以下の通りです。

|           ファイル名                                  |  ファイル名    |                  用途                 |
|-------------------------------------------------------|----------------|---------------------------------------|
| lib/agent/Oracle/script/awrracrep.sh                  | 採取スクリプト | エージェント採取スクリプト            |
| lib/Getperf/Command/Site/Oracle/AwrrptRac.pm          | pmファイル     | データ集計スクリプト                  |
| lib/Getperf/Command/Site/Oracle/AwrreportHeaderRac.pm | pmファイル     | データ集計スクリプトヘッダ情報        |
| lib/graph/Oracle/ora_*_rac.json                       | jsonファイル   | Cactiグラフテンプレート登録ルール     |

メトリック
-----------

Oracleパフォーマンス統計グラフなどの監視項目定義は以下の通りです。

| Key | Description |
| --- | ----------- |
| **パフォーマンス統計** | **RAC版AWR レポートのOracleパフォーマンス統計グラフ** |
| Elapse | **Oracle イベントの待ち時間**<br> DB CPU / SQL Exec Elapse / Wait event time / Background CPU / ...|
| Load | **Oracle ロードプロファイル** <br> Logical reads / Physical reads / Block changes / Physical writes / ... |
| Redo | **Oracle Redoサイズ** <br> 1秒あたりのOracle Redo ログ更新転送サイズ |
| Txns | **Oracle トランザクション数**<br> 1秒あたりのトランザクション実行数 |
| Execs | **Oracle SQL実行数**<br> 1秒あたりのSQL実行数 |
| Logons | **Oracle ログイン回数**<br> 1秒あたりのログイン数 |
| InterTraffic | **クラスター間ネットワーク通信量**<br> ノード間のネットワーク転送量 |
| Efficiency | **Oracle キャッシュフュージョン効率** <br> Local % / Remote % / Disk % |
| Ping Latency | **クラスター間Ping遅延**<br> ノード間のPing応答時間 |

エージェントセットアップ
========================


Statspack/AWR の設定
--------------------

エージェントホームディレクトリ下の、conf/Oracle.ini 設定ファイルの、 AWR のデータ採取スクリプトの実行オプションを設定します。
既存の AWR 採取スクリプト awrrep.sh を、 awrracrep.sh に変更します。

```
; Performance report for RAC 版 AWR
;STAT_CMD.Oracle = '_script_/awrracrep.sh -l _odir_ -d ora12c -v 1'
```

Cacti グラフ登録
================

以下のスクリプトを実行してAWR RAC版のグラフテンプレートを作成してください。

```
script/create_graph_template__oracle_rac.sh
```

グラフ登録は従来と同じです。
上記エージェントセットアップ後、データ集計が実行されると、サイトホームディレクトリの node の下にノード定義ファイルが出力されます。
出力されたノード定義ディレクトリを指定して cacti-cli を実行します。

```
cd {サイトホーム}
cacti-cli node/Oracle/{Oracleインスタンス名}/
```

AUTHOR
-----------

Minoru Furusawa <minoru.furusawa@toshiba.co.jp>

COPYRIGHT
-----------

Copyright 2014-2019, Minoru Furusawa, Toshiba corporation.

LICENSE
-----------

This program is released under [GNU General Public License, version 2](http://www.gnu.org/licenses/gpl-2.0.html).
