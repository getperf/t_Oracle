#!/usr/local/bin/perl
#
# RRDファイル更新
#
use strict;

# パッケージ読込
BEGIN {
    my $pwd = `dirname $0`;
    chop($pwd);
    push( @INC, "$pwd/libs", "$pwd/" );
}
use CGI::Carp qw(carpout);
use Getopt::Long;
use File::Basename;
use Time::Local qw(timelocal);
use DBI;
use Log::Log4perl;
use File::Temp;
use IO::All;
use Proc::Wait3 qw(wait3);
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use Net::Stomp;
use English;

use Param;

# 環境変数設定
my $RRDTOOL    = $Param::CMD_RRDTOOL;
my $RRDDIR     = $Param::RRDDIR;
my $RRDBUFSIZE = $Param::RRDBUFSIZE || 100000;

# ZABBIX環境チェック
my $ZABBIXSERVER = $Param::ZABBIXSERVER || '';
my $CMD_ZBXSEND  = $Param::CMD_ZBXSEND;

# 実行オプション
my $GREP        = '';
my $NOUPDATE    = 0;
my $RESET       = 0;
my $BAT         = 0;
my $IDIR        = '';
my $PRINT       = 0;
my $CONCURRENCY = 1; 	# タスク実行の並列度 (sumcmd)
GetOptions(
	'--batch'    => \$BAT,
	'--grep=s'   => \$GREP,
	'--noupdate' => \$NOUPDATE,
	'--reset'    => \$RESET,
	'--print'    => \$PRINT,
	'--idir=s'   => \$IDIR,
	'--thread=i'  => \$CONCURRENCY,
	)
	|| die "Usage : $0 [--batch] [--print]\n"
		. "\t[--reset] [--grep=...]\n"
		. "\t[--idir=...]\n";

# ディレクトリ設定
chop( my $HOST = `hostname` );
chop( my $PWD  = `dirname $0` );    # ~mon/script
$PWD = File::Spec->rel2abs($PWD);
my $WORK    = "$PWD/../_wk";         # ~mon/_wk
my $WORKTMP = "$PWD/../_wk/tmp";     # ~mon/_wk/tmp
my $WKLOG   = "$PWD/../_log";        # ~mon/_log
my $LOGDIR  = "$PWD/../anaysis";     # ~mon/analysis
my $SUMDIR  = "$PWD/../summary";     # ~mon/summary

# ディレクトリ作成
`/bin/mkdir -p $WKLOG`   if ( !-d "$WKLOG" );
`/bin/mkdir -p $WORK`    if ( !-d "$WORK" );
`/bin/mkdir -p $WORKTMP` if ( !-d "$WORKTMP" );

# 設定ファイルに定義したloggerを生成
Log::Log4perl::init("$PWD/log4perl.conf");
my $logger = Log::Log4perl::get_logger("pslog");

# SQLite DB環境チェック
my $SQLITE = $Param::CMD_SQLITE;
if ( !-f $SQLITE ) {
	$logger->fatal("Can't find \$CMD_SQLITE in Param.pm : $SQLITE");
	die;
}
my $SQLDB = "$WORK/monitor.db";

# スレッド共通変数(集計コマンド)
my %SUMLIST    : shared = ();		# 集計対象ファイルリスト
my %SUMSIZE    : shared = ();		# 集計対象ファイルサイズリスト
my %RRDLIST    : shared = ();		# RRD更新対象ファイルリスト

# システム共通変数
my $DATEID         = datetime();
my $TMPSEQ         = 1;
my $PROGID         = "mkrrd";
my $CMDTIMEOUT     = $Param::CMDTIMEOUT{'mkrrd'} || 600;
my $ZBXSENDTIMEOUT = $Param::CMDTIMEOUT{'zbxsend'} || 10;
my $EVENTSERVER    = $Param::EVENTSERVER || 'localhost:61613';
my ($USERNAME)     = getpwuid($UID);

# メイン
&main;
close("LOG");
exit(0);


# YYYYMMDD_HHMISS形式でカレント時刻を取得する
# 戻り値：日時
sub datetime {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
	my $dt = sprintf("%04d%02d%02d_%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
	return($dt);
}

# ワークディレクトリにテンポラリファイル名を取得する
# 戻り値：ファイル名

sub tempfile {
	my ($sfx) = @_;

	# 以下の環境変数を使用する。
	# $DATEID = datetime();
	# $TMPSEQ = 1;
	# $PROGID = "sumlog";

	# 以下のファイル形式で作成。
	# ~/perfstat/_wk/tmp/sumlog_日付_PID_SEQ.[err|out]
	my $fn = sprintf("%s/%s_%s_%d_%05d.%s",
		$WORKTMP, $PROGID, $DATEID, $$, $TMPSEQ, $sfx);

	$logger-> debug("[WORKTMP] $fn");
	$TMPSEQ ++;

	return($fn);
}

# コマンドを実行し、STDOUT,STDERRをログ出力する
# 戻り値：終了コード

sub spawn {
	my ($cmd) = @_;
	my $res;

	# コマンド起動スクリプト,STDOUT,STDERRログの一時ファイル作成
	my $shell = tempfile("sh");
	my $ofile = tempfile("out");
	my $efile = tempfile("err");

	# コマンド実行 : "command 1> file1 2> file2"
	io($shell) -> println($cmd);
	my $syscmd = "sh " . $shell . " 1> " . $ofile . " 2> " . $efile;
	$logger -> debug($syscmd);

	# タイムアウト監視をしてコマンド起動
	my $ret = 0;
	my $timeout = 0;
	eval {
		local $SIG{ALRM} = sub { die "timeout" };
		alarm $CMDTIMEOUT;

		$ret = system($syscmd);
		# 256で割って終了コード取得
		$ret  = $ret >> 8;

		alarm 0;
	};
	alarm 0;

	# 例外処理(タイムアウトのチェック)
	if($@) {
		if($@ =~ /timeout/) {
			$timeout = 1;
		}
	}

	# STDOUT, STDERR をバッファリング
	my $obuf = io($ofile) -> all if (-f $ofile);
	my $ebuf = io($efile) -> all if (-f $efile);

	# タイムアウト発生時のログ追加
	$ebuf .= "\n[TIMEOUT]" if ($timeout);

	# 標準出力、エラー出力
	if ($ret == 0) {
		$logger->info("[RC=$ret] $cmd");
		$logger->info("[STDOUT]\n$obuf") if ($obuf);
		$logger->info("[STDERR]\n$ebuf") if ($ebuf);
	} else {
		$logger->error("[RC=$ret] $cmd");
		$logger->error("[STDOUT]\n$obuf") if ($obuf);
		$logger->error("[STDERR]\n$ebuf") if ($ebuf);
	}

	# 一時ファイル削除
	unlink($shell);
	unlink($ofile);
	unlink($efile);

	return($ret);
}

# ディレクトリの作成、失敗したら親ディレクトリから順に作成する
# 戻り値：なし

sub mkdir_p {
	my ($path) = @_;

	if (!-d $path) {
		# ディレクトリの作成
		if (!mkdir($path)) {
			# 失敗したら親ディレクトリから順に作成する
			my @ptmp = split("/", $path);

			# 作成が必要な親ディレクトリの検索
			my @dirs = ();
			while( scalar(@ptmp) > 0) {
				pop( @ptmp );
				my $tpath = join("/", @ptmp);
				# 親ディレクトリが存在する場合は終了
				last if (-d $tpath);

				push(@dirs, $tpath);
			}

			# トップから順にディレクトリ作成
			for my $dir_s(reverse @dirs) {
				mkdir($dir_s);
			}
			# もう一度作成
			mkdir($path);
		}
	}
}

# 排他制御：2重起動となった場合は強制終了する。
# 戻り値：なし

sub lock {
	my ($lockfile) = @_;

	if ( my $pid = readlink($lockfile) ) {
		# "ps -ef"の2列目の値をﾁｪｯｸする｡
		if ( grep ( /^\s*(\S+)\s+$pid\s+/, `ps -ef` ) ) {
			$logger->fatal("$0 Another Process Running : PID = [$pid, $$]");
			die;
		} else {
			unlink($lockfile);
			symlink( $$, $lockfile );
		}
	} else {
		if ( !symlink( $$, $lockfile ) ) {
			$logger->fatal("$0 Still Running.");
			die;
		}
	}
}

# 履歴DBから集計対象ファイルリストを検索する
# 戻り値：ファイルリスト配列

sub getsumlist {

	# データーベースに接続する
	my $hDB;
	$logger->warn("Create SQLDB session\n");
	$hDB =
		DBI->connect( "dbi:SQLite:dbname=$SQLDB", "", "", { AutoCommit => 0 } );
	if ( !$hDB ) {
		$logger->fatal("$DBI::errstr : $!");
		die;
	}

	# sumlist検索
	my $sqlr = "select upd_date, upd_time, hostname, catname";
	$sqlr .= " from sumlist ";
	$sqlr .= " where upd_flg=2 and busy_flg=0";

	$logger->warn("$sqlr\n");
	my $sthr = $hDB->prepare($sqlr);
	my $ret  = $sthr->execute();
	if ( !$ret ) {
		$logger->fatal("$hDB->errstr : $!");
		die;
	}

	my @rtlist;
	while ( my @res = $sthr->fetchrow_array ) {
		my ( $upd_date, $upd_time, $hostname, $catname, $inpath ) = @res;
		my $path = "$hostname/$catname/$upd_date/$upd_time";
		$logger->info("SELECT [$path]");
		push( @rtlist, $path );
	}
	$sthr->finish;
	undef($sthr);

	$hDB->commit;
	$hDB->disconnect;

	return (@rtlist);
}

# 集計したファイルリストを履歴DBに更新済みとして登録する
# 戻り値：ファイルリスト配列

sub updtranlog {
	my (@infile) = @_;

	# 更新対象リスト作成
	my %rtlist;
	for my $path (@infile) {
		my @fld = split( /\//, $path );
		my $key = join( "|", @fld[ 0 .. 3 ] );
		$rtlist{$key} = 1;
	}

	# ロック待ちエラー発生時にリトライする
	my $succ  = 0;
	my $retry = 5;
	while ($succ == 0 && $retry > 0) {
		$succ = 1;
		$retry --;

		# データーベースに接続する
		my $hDB;
		$logger->warn("Create SQLDB session");
		$hDB =
			DBI->connect( "dbi:SQLite:dbname=$SQLDB", "", "", { AutoCommit => 0 } );
		if ( !$hDB ) {
			$logger->fatal("$DBI::errstr : $!");
			die;
		}

		# rtlist検索
		my $sqlr = "delete from rtlist";
		$sqlr .= " where hostname = ?";
		$sqlr .= " and catname = ?";
		$sqlr .= " and upd_date = ?";
		$sqlr .= " and upd_time = ?";

		# sumlist検索
		my $sqls = "delete from sumlist";
		$sqls .= " where hostname = ?";
		$sqls .= " and catname = ?";
		$sqls .= " and upd_date = ?";
		$sqls .= " and upd_time = ?";

		$logger->warn("$sqlr\n");
		my $sthr = $hDB->prepare($sqlr);
		my $sths = $hDB->prepare($sqls);

		for my $key ( sort keys %rtlist ) {
			my ( $host, $cat, $upd_date ,$upd_time ) = split( /\|/, $key );
			my $ret = $sthr->execute( $host, $cat, $upd_date, $upd_time );
			if ( !$ret ) {
				$logger->warn("SQLite exec [TETRY] $retry");
				$succ = 0;
				sleep(1);
				last;
			} else {
				$logger->warn("[DEL rtlist] [$upd_date, $upd_time, $host, $cat]");
			}
			my $ret = $sths->execute( $host, $cat, $upd_date, $upd_time );
			if ( !$ret ) {
				$logger->warn("SQLite exec [TETRY] $retry\n");
				$succ = 0;
				sleep(1);
				last;
			} else {
				$logger->warn("[DEL sumlist] [$upd_date, $upd_time, $host, $cat]");
			}
		}
		$sthr->finish;
		$sths->finish;
		undef($sthr);
		undef($sths);

		$hDB->commit;
		$hDB->disconnect;
	}
	return (1);
}

# 集計したファイルリストを履歴DBに更新済みとして登録する
# 戻り値：ファイルリスト配列

sub updhistlog {
	my (@histdat) = @_;

	# データーベースに接続する
	my $hDB;
	$logger->warn("Create SQLDB session");
	$hDB =
		DBI->connect( "dbi:SQLite:dbname=$SQLDB", "", "", { AutoCommit => 0 } );
	if ( !$hDB ) {
		$logger->fatal("$DBI::errstr : $!");
		die;
	}

	# sumhist履歴(houry)検索SQL
	my $sqlr_rrdhist_hourly  = "select cnt_ok, cnt_ng from rrdhist_hourly";
	   $sqlr_rrdhist_hourly .= " where upd_date=? and upd_time=?";
	   $sqlr_rrdhist_hourly .= " and hostname=? and catname=? and inpath=?";
	my $sthr_rrdhist_hourly  = $hDB->prepare($sqlr_rrdhist_hourly);

	# sumhist履歴(dayly)検索SQL
	my $sqlr_rrdhist_dayly  = "select cnt_ok, cnt_ng from rrdhist_dayly";
	   $sqlr_rrdhist_dayly .= " where upd_date=? ";
	   $sqlr_rrdhist_dayly .= " and hostname=? and catname=? and inpath=?";
	my $sthr_rrdhist_dayly  = $hDB->prepare($sqlr_rrdhist_dayly);

	# sumlist履歴(hourly)登録SQL
	my $sqlc_rrdhist_hourly = "replace into rrdhist_hourly values(?, ?, ?, ?, ?, ?, ?)";
	my $sthc_rrdhist_hourly = $hDB->prepare($sqlc_rrdhist_hourly);

	# sumlist履歴(dayly)登録SQL
	my $sqlc_rrdhist_dayly = "replace into rrdhist_dayly values(?, ?, ?, ?, ?, ?)";
	my $sthc_rrdhist_dayly = $hDB->prepare($sqlc_rrdhist_dayly);

	for my $res(@histdat) {
		# 先頭の"/"は除外する。
		my ($path, $okcnt0, $ngcnt0) = split( /\|/, $res );
		my ($hostname, $catname, $upd_date, $upd_time, @rtfiles) = split(/\//, $path);
		my $rtfile = join("/", @rtfiles);

		# 履歴テーブル(hourly)に登録
		$sthr_rrdhist_hourly->execute($upd_date, $upd_time, $hostname, $catname, $rtfile);
		my ($okcnt, $ngcnt) = $sthr_rrdhist_hourly->fetchrow_array;
		$okcnt += $okcnt0;
		$ngcnt += $ngcnt0;
		my $ret = $sthc_rrdhist_hourly->execute($upd_date, $upd_time, $hostname, $catname, $rtfile, 
			$okcnt, $ngcnt);
		my $msg = "[REPLACE SUMLIST_HOURLY] $upd_date, $upd_time, $hostname, $catname, $rtfile, $okcnt, $ngcnt";
		if ( !$ret ) {
			$logger->error("$! : $msg");
		} else {
			$logger->info($msg);
		}

		# 履歴テーブル(dayly)に登録
		$sthr_rrdhist_dayly->execute($upd_date, $hostname, $catname, $rtfile);
		my ($okcnt2, $ngcnt2) = $sthr_rrdhist_dayly->fetchrow_array;
		$okcnt2 += $okcnt0;
		$ngcnt2 += $ngcnt0;
		my $ret2 = $sthc_rrdhist_dayly->execute($upd_date, $hostname, $catname, $rtfile, $okcnt2, $ngcnt2);
		my $msg2 = "[REPLACE SUMLIST_DAYLY] $upd_date, $hostname, $catname, $rtfile, $okcnt2, $ngcnt2";
		if ( !$ret2 ) {
			$logger->error("$! : $msg2");
		} else {
			$logger->info($msg2);
		}
	}

	$sthr_rrdhist_hourly->finish;
	$sthr_rrdhist_dayly->finish;
	$sthc_rrdhist_hourly->finish;
	$sthc_rrdhist_dayly->finish;
	$hDB->commit;

	undef $sthr_rrdhist_hourly;
	undef $sthr_rrdhist_dayly;
	undef $sthc_rrdhist_hourly;
	undef $sthc_rrdhist_dayly;

	$hDB->disconnect;

	return (1);
}

# 文字列をUNIX時刻に変換
# 戻り値:UNIX時刻
sub time2sec {

	# 入力：YYYY/MM/DD, HH:MI:SS
	my ( $dt, $tm ) = @_;
	my ( $YY, $MM, $DD ) = split( /\//, $dt );
	my ( $hh, $mm, $ss ) = split( /:/,  $tm );

	my $sec;
	my $valid = eval {
		$sec = timelocal( $ss, $mm, $hh, $DD, $MM - 1, $YY );
	};
	if ($valid and !$@) { # $@ は判定エラーが生じた場合
		return $sec;
	} else {
		return 0;
	}
}

# RRDファイル作成
# 戻り値：crerrd.plのリターンコード
sub crerrddat {

	# 入力：RRDファイル
	my ($rrdfile) = @_;
	print("# $rrdfile\n") if ($PRINT);

	# RRDファイルが無い場合は新規作成
	if ( !-f "$RRDDIR/$rrdfile" ) {

		# ファイル名からディレクトリを分解して、ディレクトリがなければ新規作成
		my ( $fname, $path, $suffix ) = fileparse("$RRDDIR/$rrdfile");
		if ( !-d $path ) {
			# プリントオプション付の場合は標準出力
			if ($PRINT) {
				print("/bin/mkdir -p $path") ;
			} else {
				mkdir_p($path) ;
			}
		}

		my $cmd = "$Param::CMD_PERL $PWD/crerrd.pl --path=$rrdfile";
		$logger->warn("[$$][Exec] crerrd.pl --path=$rrdfile");

		if ($PRINT) {
			print("$cmd\n");
		} else {
			# crerrd.plスクリプト実行
			my $ret = spawn($cmd);

			return $ret;
		}
	}
}

# {ホスト/カテゴリ/日付/時刻/ファイル.txt}を解析する。
# 戻り値：RRDキー,RRDファイル名
sub ckrrdcmd {
	my ($datapath) = @_;

	# 入力：項目名,RRDファイル,入力パス
	my ( $fname, $rrdfile );

	# データファイルをディレクトリ毎に分解
	$datapath =~ s/^\.\///g;
	my @ptmp   = split( "/", $datapath );
	my $host   = shift(@ptmp);
	my $cat    = shift(@ptmp);
	my $dt     = shift(@ptmp);
	my $tm     = shift(@ptmp);
	my $fn     = pop(@ptmp);
	my $subdir = join( "/", @ptmp );

	# RRDファイル抽出
	if ( $fn =~ /(.*)\.txt/ ) {
		if ($subdir) {
			$rrdfile = sprintf( "%s/%s/%s/%s.rrd", $host, $cat, $subdir, $1 );
		}
		else {
			$rrdfile = sprintf( "%s/%s/%s.rrd", $host, $cat, $1 );
		}
	}
	else {
		$logger->warn("UNKOWN File type : $datapath");
		return (undef, undef);
	}

	# ファイルID抽出
	$logger->debug("$host,$cat,$dt,$tm,$fn,$subdir");
	for my $key ( sort { $b cmp $a } keys %Param::RRDITEM ) {
		my ( $datkey, $hostkey ) = split( ',', $key );

		if ( $hostkey eq '' ) {
			# [項目] でチェック
			if ( my $idx = index( $fn, $datkey ) == 0 ) {
				$fname = $datkey;
				last;
			}
		}
		else {
			# [項目,ホスト] でチェック
			if ( $hostkey eq $host ) {
				if ( my $idx = index( $fn, $datkey ) == 0 ) {
					$fname = join( '|', ( $datkey, $host ) );
					last;
				}
			}    # [項目,ホストグループ] でチェック
			elsif ( $hostkey eq $Param::HOSTGRP{$host} ) {
				if ( my $idx = index( $fn, $datkey ) == 0 ) {
					$fname = join( '|', ( $datkey, $hostkey ) );
					last;
				}
			}
		}
	}
	if ( $fname eq '' ) {
		return( undef, $rrdfile );
	}

	$logger->debug("[FNAME] $fname");

	return(( $fname, $rrdfile ));
}

# 集計対象ファイルからrrdtool updateコマンドを生成する
# 戻り値：コマンド行配列
sub readdat {
	my ($rrdfile, $sumfile) = @_;

	$logger->debug("[READ] START $sumfile");

	# Param.pmからRRDデータのDS列の索引を取得
	my $rrdkey = $RRDLIST{ $rrdfile };

	$rrdkey=~s/\|/,/;					# iostat|aix を iostat,aixに変換

	$logger->debug("[READ][RRDFILE] $rrdfile");
	$logger->debug("[READ][RRDKEY]  $rrdkey");

	my @ds;
	my @item = split( /\n/, $Param::RRDITEM{$rrdkey} );
	for my $key (@item) {
		my @ptmp = split( /:/, $key );
		push( @ds, shift(@ptmp) );
	}
	$logger->debug("[READ][DS] " . join("|", @ds));

	# 性能データ読込み
	if ( !open( IN, "$SUMDIR/$sumfile" ) ) {
		$logger->warn("Can't open file $SUMDIR/$sumfile : $!");
		next;
	}

	my @datbuf;
	my @cmdbuf;
	my $row = 1;
	while (<IN>) {
		chop;
		my $line = $_;
		$line =~ s/,//g;
		my @item = split( /\s+/, $line );
		my $dt   = shift(@item);
		my $tm   = shift(@item);
		# 08/09/07 16:00:30
		if ( $row > 1 && $_ =~ /^\d+\/\d+\/\d+\s+\d+:\d+/ ) {
			my $sec = time2sec( $dt, $tm );
			my $dat = $sec;
			for my $idx (@ds) {
				$dat .= ':' . $item[$idx];
			}
			push( @cmdbuf, "update $rrdfile $dat\n" );
			push( @datbuf, "$sumfile|$dt|$tm\n" );
		}
		$row++;
	}
	close(IN);

	return (\@datbuf, \@cmdbuf);
}

# RRD更新コマンド実行ログ解析
# 戻り値：登録件数,エラー件数
sub ckrrdupdlog {
	# 入力値 : 出力ログ(配列)
	my ($refdat, $refout) = @_;

	my @datbuf = @{ $refdat };
	my @outbuf = @{ $refout };

	# コマンド入力バッファと出力バッファの行数が異なる場合はエラー
	my $datn = scalar( @datbuf );
	my $outn = scalar( @outbuf );
	if ($outn != $datn) {
		$logger->error("rrdtool update : Lines($outn/$datn)");
	}

	# 
	my %errmsg = ();
	my %updres = ();
	
	for my $res (@outbuf) {
		chop($res);
		$logger->debug("res : $res");
		my $dat = shift(@datbuf);
		chop($dat);

		my ($sumfile, $dt, $tm) = split( /\|/, $dat );
		my $ref1  = $updres{$sumfile};
		my $okcnt = ${ $ref1 }{'OK'};
		my $ngcnt = ${ $ref1 }{'NG'};

		if ($res =~ /^OK/) {
			$okcnt ++;
		} elsif ($res =~ /^ERROR: (.*?): (.*)$/) { 			# RRDTool 1.3以上
			my ($updrrd, $msg) = ($1, $2);
			$msg =~ s/illegal attempt to update using time \d+ when/illegal update time/g;
			$msg =~ s/last update time is \d+//g;
			$msg =~ s/\(minimum one second step\)//g;
			$msg =~ s/expected (\d+) data source readings \(got (\d+)\) .*/expected $1 data (got $2) .../g;
			$msg =~ s/expected timestamp not found in data source from (\d+)/timestamp not found/g;
			$errmsg{$msg} ++;

			$ngcnt ++;
		} elsif ($res =~ /^ERROR: (.*)$/) {					# RRDTool 1.2
			my ($msg) = ($1);

			$msg =~ s/illegal attempt to update using time \d+ when/illegal update time/g;
			$msg =~ s/last update time is \d+//g;
			$msg =~ s/\(minimum one second step\)//g;
			$msg =~ s/expected (\d+) data source readings \(got (\d+)\) .*/expected $1 data (got $2) .../g;
			$msg =~ s/expected timestamp not found in data source from (\d+)/timestamp not found/g;
			$errmsg{$msg} ++;

			$ngcnt ++;
		} else {
			$errmsg{'unkown error'} ++;

			$ngcnt ++;
		}

		my %res = (
			'OK' => $okcnt,
			'NG' => $ngcnt,
		);
		$updres{$sumfile} = \%res ;
	}

	for my $key(sort keys %errmsg) {
		$logger->warn("[$$][$errmsg{$key}/$datn] $key");
	}

	return( \%updres );
}

# RRDファイル名リストを%SUMLISTに登録
# 戻り値：検索ファイル数
sub findrrd {

	# 入力：集計データパス
	my ($inpath) = @_;

	# findコマンド実行して該当パスのファイルリスト抽出
	$inpath =~ s/^\///g;    # 先頭の"/"を取り除く
	my $cmd = "(cd $SUMDIR; $Param::CMD_FIND $inpath -name \"*.txt\")";
	$logger->info( $cmd );

	my $nfile   = 0;

	if (!-d "$SUMDIR/$inpath") {
		return 0;
	} elsif (!open( IN, "$cmd|" )) {
		$logger->error("Can't open file $cmd : $!");
		return 0;
	} else {
		while (<IN>) {
			my $outfile = $_;
			chop($outfile);
			$outfile =~ s/^\.\///g;     # 先頭の"./"を取り除く
			my ( $host, $cat, $dt, $tm, @flist ) = split( "/", $outfile );
			my $outpath = join( "/", @flist);

			# --grepオプション付の場合はキーワードに一致するファイルのみを抽出
			if ( $GREP ) {
				next if ($_ !~ /$GREP/ );
			}

			# RRD定義情報から項目IDとRRDファイルを抽出する
			my ( $rrdkey, $rrdfile ) = ckrrdcmd($outfile);

			# ファイル属性からサイズを取得して累計値を %SUMSIZE に登録
			my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, 
			    $atime, $mtime, $ctime, $blksize, $blocks) = stat("$SUMDIR/$outfile");
			$SUMSIZE{ $rrdfile } += $size;

			$logger->info("[CHECK] $outfile");
			if ( $rrdkey eq '' ) {
				$logger->info("[RES]   Size=$size,UNKNOWN");
			} else {
				$logger->info("[RES]   Size=$size,RRDKey=$rrdkey,RRDFile=$rrdfile");
			}

			# RRDKEYが存在し、集計ファイルサイズが0より大きい場合はRRD更新対象に登録
			$RRDLIST{$rrdfile} = $rrdkey if ($rrdkey ne '' && $size > 0);

			# RRDファイル名をキーにしてRRD IDを登録
			if ($SUMLIST{$rrdfile} eq '') {
				$SUMLIST{$rrdfile} = $outfile;
			} else {
				$SUMLIST{$rrdfile} .= "|" . $outfile;
			}
			$nfile ++;
		}
	}
	close(IN);

	return($nfile);
}

# 集計処理ワーカー
# 入力：集計ファイルハンドラー,集計ID{順番/件数},集計キー
# 戻り値：なし

sub consumerSumcmd {
	my ($fh, $consumerid, @rrdfiles) = @_;

	my $t0     = [gettimeofday];
	my @res    = ();
	my $nrrd   = scalar(@rrdfiles);

	# rrdtool update コマンド、結果出力バッファ
	my @cmdbuf = ();
	my @datbuf = ();
	my @sumbuf = ();

	# 集計対象ファイルを基に、集計対象ファイルを取得
	# 集計対象ファイルは{ホスト/カテゴリ/RRDファイル名}の複数件が対象
	my $exitcode = 0;
	for my $rrdfile( @rrdfiles ) {
		my $rrdkey = $RRDLIST{$rrdfile};

		# --rmオプションの場合はファイルを事前削除
		my $rrdkey = $RRDLIST{ $rrdfile };
		if ( $Param::RRDOPT{$rrdkey} =~ /-rm/ ) {
			$logger->warn("[DEL] $rrdfile");
			unlink("$RRDDIR/$rrdfile") if ( -f "$RRDDIR/$rrdfile" );
		}

		# RRDファイルを作成する
		crerrddat($rrdfile);

		# コマンド実行
		my $exitcode = 0;

		# プリントオプション付きの場合はヘッダ情報出力
		print("\n# $rrdfile\n") if ($PRINT);

		# 集計対象ファイル{ホスト/カテゴリ/日付/時刻/集計ファイル}を取得。
		my $nsumfile = 0;
		for my $sumfile( split(/\|/, $SUMLIST{ $rrdfile }) ) {
			$nsumfile ++;
			$logger->info("[$$][READ] $sumfile");
			my ( $refdat, $refcmd ) = readdat( $rrdfile, $sumfile );
			push( @cmdbuf, @{ $refcmd });
			push( @datbuf, @{ $refdat });
		}
		$logger->warn("[$$][$rrdkey,$rrdfile][$nsumfile]");
	}
	my $rows = scalar( @datbuf );
	$logger->warn("[$$][READ] $rows rows");

	# プリントオプション付の場合はコマンドを標準出力
	if ($PRINT) {
		print "$RRDTOOL - <<EOF\n";
		print @cmdbuf;
		print "EOF\n";
	} else {
		# RRDデータ登録スクリプト作成
		my $scirpt = tempfile("sh");
		io($scirpt) -> print(("$RRDTOOL - <<EOF\n", @cmdbuf, "EOF\n"));

		# RRDデータ登録実行
		my $cmd = "(cd $RRDDIR; /bin/sh $scirpt)";
		my @resbuf = `$cmd`;
		$logger->warn("ERROR: $? $!") if ($?);
		unlink($scirpt);

		# 実行ログを解析し、正常/エラー件数を集計
		my $refupdres = ckrrdupdlog(\@datbuf, \@resbuf);
		my %updres = %{ $refupdres };
		for my $key(sort keys %updres) {
			my $okcnt = ${ $updres{$key} }{'OK'};
			my $ngcnt = ${ $updres{$key} }{'NG'};
			push( @sumbuf, "$key,$okcnt,$ngcnt" );
		}
	}

	# 終了コードと処理時間をログ出力
	my $elapsed = tv_interval ($t0); 
	my $msg = sprintf("[%d] Elapse=%5.2f", $$, $elapsed);
	$logger->warn($msg);

	# 集計対象ファイルとコマンド終了コードをファイル出力
	# {/ホスト/カテゴリ/日付/時刻/ファイル,終了コード}の形式で出力
	if (!$PRINT) {

		# 出力を排他制御するため，ファイル名で開き直す
		my $cfh;
		open $cfh, '>>', $fh->filename or die $!;

		# ファイルの排他制御
		flock $cfh, 2 or die $!;
		seek $cfh, 0, 1;

		for my $res (@sumbuf) {
			print $cfh "$res\n";
		}

		flock $cfh, 0;
		close($cfh);
	}
}

sub main {
	my $cmd;

	$logger->warn("============== BEGIN ==================================");
	my $t0 = [gettimeofday];

	# rrd対象ディレクトリとファイル件数
	my $npath = 0;
	my $nfile = 0;

	# ~/perfstat/summary/下のファイルを全件検索
	if ($RESET) {
		my %findlist;
		my $cmd = "(cd $SUMDIR; $Param::CMD_FIND . -name \"[0-9]*\")";
		$logger->warn($cmd);
		if (!open( IN, "$cmd|" )) {
			$logger->fatal("Can't open $cmd : $!");
			die;
		}
		while (<IN>) {
			chop($_);
			$_ =~ s/^\.\///g;    # 先頭の"./"を取り除く
			$findlist{$_} = 1;
		}
		close(IN);

		for my $path ( sort %findlist ) {
			my @ptmp = split(/\//, $path);
			next if (scalar(@ptmp) != 4);

			$npath ++;
			$logger->warn("[PATH] $path:" . scalar(@ptmp) );
			$nfile += findrrd($path);
		}
	}

	# 実行オプション(--idir=[...])で指定したディレクトリを検索
	elsif ($IDIR) {
		$npath ++;
		$nfile += findrrd( $IDIR );
	}

	# 更新履歴DBから検索
	else {
		my @inlist = getsumlist();
		for my $path (@inlist) {
			$npath++;
			$logger->debug("[mkrrd] $path");
			$nfile += findrrd( $path );
		}
	}

	$logger->warn("[Find path] DIRS=$npath,FILES=$nfile");

	$logger->warn("============== Execute RRDTool ========================");
	# 集計結果データファイルスクリプター
	my $fh = new File::Temp(UNLINK => 0);
	$logger->info("tmp file: $fh->filename");

	# 集計リストキューイング
	my $active   = 0;
	my $cnt      = 0;
	my $bufsize  = 0;
	my @rrdfiles = ();

	# 異常値検知対象のrrdファイルの場合は最終更新日付を%ev_lastupdに登録
	# $ev_lastupd{"$rrdfile,$pos"} = $last;
	my %ev_lastupd;
	for my $rrdfile (sort keys %RRDLIST ) {
		my $rrdkey = $RRDLIST{$rrdfile};
		# RRDITEM の要素で "POS:ITEM:TYPE:OPT" の4要素からなる場合にチェックする
		my @item = split( /\n/, $Param::RRDITEM{$rrdkey} );
		for my $key (@item) {
			my @ptmp = split( /:/, $key );
			next if (scalar(@ptmp) != 4);

			# RRDITEM が ".:.:.:FAILURE" の場合はrrdファイルと位置をHWイベントに登録
			my $pos = shift(@ptmp);
			my $ds  = shift(@ptmp);
			my $opt = pop(@ptmp);
			next if ($opt ne 'FAILURE');

			$logger->debug("[CHECK][HW] $rrdfile,$pos");
			my $last = time - 300;
			if (!-f "$RRDDIR/$rrdfile") {
				$logger->warn("[HW][CHECK LASTUPD] Can't find $rrdfile. use default last=-300");
				$ev_lastupd{"$rrdfile,$pos,$ds"} = $last;
			} else {
				my $buf = `$RRDTOOL last $RRDDIR/$rrdfile`;
				if ($buf=~/(\d+)/) {
					$ev_lastupd{"$rrdfile,$pos,$ds"} = $1;
				} else {
					$logger->warn("Exec error : rrdtool last $rrdfile, use default last=-300.");
					$ev_lastupd{"$rrdfile,$pos,$ds"} = $last;
				}
			}
		}
	}

	# RRD登録
	my $ncnt = scalar(keys %RRDLIST);
	for my $rrdfile ( sort keys %RRDLIST ) {
		$cnt++;
		my $rrdkey = $RRDLIST{$rrdfile};
		my $seq    = sprintf("%d/%d", $cnt, $ncnt);

		# RRD Update対象ファイルに追加
		push( @rrdfiles, $rrdfile );

		# ファイルサイズを取得し、類型値がRRDBUFSIZEを超えた場合に子プロセス起動
		$bufsize += $SUMSIZE{ $rrdfile };
		if ($bufsize > $RRDBUFSIZE) {

			$logger->warn("[MKRRD][EXECUTE] $seq");
			# ワーカープロセス起動
			unless (fork()) {
				# ワーカプロセスでRRD登録処理実行
				consumerSumcmd($fh, $seq, @rrdfiles);
				exit;
			}

			@rrdfiles = ();
			$bufsize  = 0;
			# 空きが有ればとりあえず起動
			$active ++;
			next if ($active < $CONCURRENCY);

			# 終了したワーカプロセスの集計
			$logger->info("[WAIT] BEGIN");

			if (my ($child) = wait3(1)) {
				$logger->info("[EXIT1] pid=$child");
			}
			$active --;
			$logger->info("[WAIT] END");
		}
	}

	# 最後は親プロセスでRRD登録処理実行
	if (scalar(@rrdfiles) > 0) {
		consumerSumcmd($fh, "END", @rrdfiles);
	}

	# 残りのワーカプロセスのデータ処理
	while (my ($child) = wait3(1)) {
		$logger->warn("[EXIT2] pid=$child");
	}

	# 更新履歴DB登録
	$logger->warn("============== Update Summary Log DB ==================");
	# 履歴ログ更新
	# ファイルハンドルをつかんでいるので消しても問題なし
	unlink $fh->filename;

	# コマンド実行履歴集計
	my @histlist = ();
	while (<$fh>) {
		chop;
		# {ファイルパス名,終了コード}を解析
		my ($fn, $ok, $ng) = split(",", $_);

		$ok = 0 if ($ok eq '');
		$ng = 0 if ($ng eq '');

		push(@histlist, join("|", ($fn, $ok, $ng)));
	}
	updhistlog(@histlist);

	# トランザクションログ更新
	my @outlist = ();
	for my $key (sort keys %SUMLIST) {
		push(@outlist, split(/\|/, $SUMLIST{$key} ));
	}
	updtranlog(@outlist) if (!$NOUPDATE);

	# rrdfetch ... FAIRURES の予測結果をJMS送信
	$logger->warn("============== Update Event Log DB ===================");

	# rrdfetch ... FAIRURES の予測結果を@ev_resに登録
	my %ev;
	for my $key (sort keys %ev_lastupd) {
		next if ($key!~/(.*),(\d*),(.*)/);
		my ($rrdfile, $pos, $ds) = ($1, $2, $3);
		my $last = $ev_lastupd{$key};

		# rrdtool fetch ... FAILURE を実行し、指定列の値に1が存在するかをチェック
		my @buf = `$RRDTOOL fetch -s $last $RRDDIR/$rrdfile FAILURES`;
		if ($?) {
			$logger->errror("Error : rrdtool fetch -s $last $rrdfile FAILURES");
		}
		my $flg = 0;
		for my $ln(@buf) {
			chop($ln);
			next if ($ln!~/^(\d+): (.*)$/);
			my ($tm, $body) = ($1, $2);
			next if ($tm < $last);
			my @attr = split(/\s/, $body);
			next if ($attr[$pos] eq 'nan');
			$flg = 1 if ($attr[$pos] == 1);
		}
		my ($ss, $mi, $hh, $dd, $mm, $yy) = localtime($last);
		my $tms = sprintf("%04d:%02d:%02d %02d:%02d:%02d", $yy + 1900, $mm + 1, $dd, $hh, $mi, $ss);

		next if ($rrdfile!~/(.*?)\/.*\/(.*)\.rrd/);
		my ($host, $rrd) = ($1, $2);
		my $param = lc 'ng.' . $rrd . '.' . $ds;
		$ev{ $host . '|' . $param } = $flg;
		$logger->warn("[ZBX Send] $host, $param, $flg");
	}

	# zabbix_sender実行パラメータチェック
	my ($zbxhost, $zbxport);
	if ($ZABBIXSERVER=~/^(.+?):(\d+?)$/) {
		($zbxhost, $zbxport) = ($1, $2);
	} else {
		$logger->warn("Can't Read ZABBIXSERVER(Param.pm): $ZABBIXSERVER");
	}

	# ZABBIX データ送信
	if ( !-f $CMD_ZBXSEND ) {
		$logger->warn("Can't find \$CMD_ZBXSEND in Param.pm : Ignore");
	} else {
		# タイムアウト監視をしてコマンド起動
		my $timeout = 0;
		# push(@ev_res, "$tms,$rrdfile,$ds,$flg");
		# zabbix_sender -z <Server> -p <Server port> -s <Hostname> -k <Key> -o <Key value>
		for my $key(sort keys %ev) {
			my $val = $ev{$key};
			my ($host, $param) = split(/\|/, $key);
			my $cmd = "$CMD_ZBXSEND -v -z $zbxhost -p $zbxport -s $host -k $param -o $val";

			if ($timeout == 1) {
				$logger -> warn("[SKIP] $cmd");
				next;
			} else {
				$logger -> warn("[EXEC] $cmd");
			}

			eval {
				local $SIG{ALRM} = sub { die "timeout" };
				alarm 4;

				my $obuf = `$cmd`;
				if (!$?) {
					$timeout = 1 if ($obuf=~/Timeout/);
					$logger -> warn("[Error] $obuf");
				}
				alarm 0;
			};
			alarm 0;
			my $res = $@;
			# 例外処理(タイムアウトのチェック)
			if ($res=~/timeout/) {
				$logger -> warn("[TIMEOUT] Skip zabbix_sender.");
				$timeout = 1;
			}
		}
	}

	my $elapsed = tv_interval ($t0); 
	$logger->warn("Total Elapse = $elapsed");
	$logger->warn("========================= END =========================");
}

