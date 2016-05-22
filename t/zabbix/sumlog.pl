#!/usr/local/bin/perl
#
# ログの集計
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
use DBI;
use Log::Log4perl;
use File::Temp;
use IO::All;
use Symbol;
use Proc::Wait3;
use IPC::Open3;
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use Net::Stomp;
use Socket;
use English;

use Param;

# 環境変数設定
$ENV{'LANG'} = 'C';
my $DEBUG = 0;

# 実行オプションチェック
my $RESET         = 0;
my $ONECYCLE      = 0;
my $MKRRD         = 0;
my $PRINT         = 0;
my $NOUPDATE      = 0;
my $IDIR          = '';
my $GREP          = '';
my $CONCURRENCY   = 1; 	# タスク実行の並列度 (sumcmd)
GetOptions(
	'--onecycle'  => \$ONECYCLE,
	'--reset'     => \$RESET,
	'--noupdate'  => \$NOUPDATE,
	'--grep=s'    => \$GREP,
	'--print'     => \$PRINT,
	'--idir=s'    => \$IDIR,
	'--thread=i'  => \$CONCURRENCY,
	)
	|| die "Usage : $0 [--onecycle] [--thread=n] [--print]\n"
		. "\t[--reset] [--grep=...]\n"
		. "\t[--idir=...]\n";

# ディレクトリ設定
my $HOST = `hostname`;
chop($HOST);
my $PWD = `dirname $0`;
chop($PWD);    # ~mon/script
$PWD = File::Spec->rel2abs($PWD);
my ($USERNAME) = getpwuid($UID);

my $WORK    = "$PWD/../_wk";         # ~mon/_wk
my $WORKTMP = "$PWD/../_wk/tmp";     # ~mon/_wk/tmp
my $WKLOG   = "$PWD/../_log";        # ~mon/_log
my $LOGDIR  = "$PWD/../analysis";    # ~mon/analysis
my $SUMDIR  = "$PWD/../summary";     # ~mon/summary

# ディレクトリチェック
`/bin/mkdir -p $WKLOG`   if ( !-d "$WKLOG" );
`/bin/mkdir -p $WORK`    if ( !-d "$WORK" );
`/bin/mkdir -p $WORKTMP` if ( !-d "$WORKTMP" );
`/bin/mkdir -p $LOGDIR`  if ( !-d "$LOGDIR" );

# 設定ファイルに定義したloggerを生成
Log::Log4perl::init("$PWD/log4perl.conf");
my $logger = Log::Log4perl::get_logger("pslog");

# DB環境チェック
my $SQLITE = $Param::CMD_SQLITE;
if ( !-f $SQLITE ) {
	$logger->fatal("Can't find \$CMD_SQLITE in Param.pm : $SQLITE");
	die;
}
my $SQLDB = "$WORK/monitor.db";

# システム共通変数
my $DATEID         = datetime();
my $TMPSEQ         = 1;
my $PROGID         = "sumlog";
my $CMDTIMEOUT     = $Param::CMDTIMEOUT{'sumlog'}  || 600;
my $ZBXSENDTIMEOUT = $Param::CMDTIMEOUT{'zbxsend'} || 3;

# ZABBIX環境チェック
my $ZABBIXSERVER = $Param::ZABBIXSERVER || '';
my $CMD_ZBXSEND  = $Param::CMD_ZBXSEND;
my %PROCSERIAL   = map { $_ => 1 } split(/|/, $Param::PROCSERIAL); 

# スレッド共通変数(集計コマンド)
my %SUMLIST    : shared = ();		# 集計対象ディレクトリリスト
my %SUMCMD     : shared = ();		# 集計コマンドリスト
my %SUMRESULT  : shared = ();		# コマンド実行結果リスト

# スレッド共通変数(環境変数)
my %ENV_IFILE  : shared = ();		# 環境変数(入力ファイル)
my %ENV_IDIR   : shared = ();		# 環境変数(入力ディレクトリ)
my %ENV_ODIR   : shared = ();		# 環境変数(出力ディレクトリ)

# メイン
&main();
close("LOG");
exit(0);

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

sub spawn2 {
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

	return($ret, $obuf, $ebuf);
}

# 引数のホストに対してポートスキャンする
# 戻り値：成否
sub ck_service {
	my ($host, $port) = @_;

	my $iaddr = inet_aton($host);
	if (!$iaddr) {
		$logger->error("[inet_aton] $host:$port");
		return -1;
	}
	my $addr = pack_sockaddr_in($port, $iaddr);
	if (!socket(SOCKET, PF_INET, SOCK_STREAM, 0)) {
		$logger->error("[socket] $host:$port");
		return -1;
	}
	if (!connect(SOCKET, $addr)) {
		$logger->error("[connect] $host:$port");
		return -1;
	}
	if (!close(SOCKET)) {
		$logger->error("[socket close] $host:$port");
		return -1;
	}

	return 1;
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

# ログファイルから実行コマンドをチェックし、%SUMCMDに登録
# 戻り値：なし

sub cksumcmd {

	# 入力 : ログファイルパス
	# 例：/noir/HW/20061119/1707/sar_u.txt
	#     /noir/HW/20061119/1707/df/root.txt
	my ($filepath) = @_;

	# ファイル以外の場合は省略
	my $inpath = "$LOGDIR/$filepath";
	if ( !-f $inpath ) {
		$SUMCMD{$filepath} = 'NULL';
		return;
	}

	# ファイル名とディレクトリを分解
	my ( $fname, $path, $suffix ) = fileparse("$inpath");

	# 出力先ディレクトリ作成
	my $opath = $path;
	$opath =~ s/analysis/summary/g;

	# ファイル名からコマンド指定
	# 先頭の"/"は取り除く
	$filepath=~s/^\///g;
	my ( $host, $id, $date, $tm, @flist ) = split( "/", $filepath );

	$logger->debug("CHECK [ $filepath ]");
	$logger->info("CHECK [ $host, $id, $date, $tm, $fname ]");
	my $cmd;
	my $key1    = join( ",", ( $fname, $host ) );
	my $hostgrp = $Param::HOSTGRP{$host};
	my $key2    = join( ",", ( $fname, $hostgrp ) );

	if ( $Param::REFCMD{$key1} ) {    # [ログファイル,ホスト]でチェック
		$cmd = $Param::REFCMD{$key1};
	}
	elsif ( $Param::REFCMD{$key2} ) {    # [ログファイル,ホストグループ]でチェック
		$cmd = $Param::REFCMD{$key2};
	}
	elsif ( $Param::REFCMD{$fname} ) {    # [ログファイル]でチェック
		$cmd = $Param::REFCMD{$fname};
	}
	else {
		$SUMCMD{$filepath} = 'NULL';
		return;
	}

	# コマンドリストに登録
	$cmd =~ s/_idir_/$path/g;
	$cmd =~ s/_odir_/$opath/g;
	$cmd =~ s/_cwd_/$PWD/g;

	# 集計コマンドリスト登録
	$SUMCMD{$filepath} = $cmd;

	my $key;
	if ($PROCSERIAL{$id} == 1) {
		$key = join('|', ($host, $id, $fname));
	} else {
		$key = join('|', ($host, $id, $date, $tm, $fname));
	}

	$SUMLIST{$key} .= '|' . $filepath;

	# ディレクトリ、ファイル名を登録
	$ENV_IFILE{$filepath} = $fname;
	$ENV_IDIR{$filepath}  = $path;
	$ENV_ODIR{$filepath}  = $opath;
}

# ファイルから集計対象リストを検索する
# 戻り値: ファイルリスト配列
sub getsumlist_file {
	my @infiles;
		
	# ~/perfstat/analysis下のファイル検索
	my $cmd = "(cd $LOGDIR; $Param::CMD_FIND .)";
	$logger->info("$cmd\n");
	
	if (!open( IN, "$cmd|" )) {
		$logger->error("Can't open $cmd : $OS_ERROR");
		die;
	}
	while (<IN>) {
		chop($_);
		$_ =~ s/^\.//g;			# 先頭の"."を取り除く
		$_ =~ s/\s+$//g;		# 末尾の" "を取り除く

		# パス形式チェック
		# [例：/reddragon/HW/20070707_2240/Memory.txt]
		my @path = split( /\//, $_ );
		if ( $path[3] !~ /^[0-9]/ || scalar(@path) < 5 ) {
			$logger->warn("Check error sumlist : $_");
			next ;
		}
		# パス登録
		push( @infiles, join( '/', @path ) );
	}
	close(IN);
    
	return(@infiles);
}

# 履歴DBから集計対象ファイルリストを検索する
# {/ホスト/カテゴリ/日付/時刻/ファイル名}の集計対象リストを作成する
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
	my $sqlr;
	if ( !$ONECYCLE ) {
		$sqlr  = "select s.upd_date, s.upd_time, s.hostname, s.catname, r.inpath";
		$sqlr .= " from sumlist s, rtlist r";
		$sqlr .= " where s.upd_flg=1 and s.busy_flg=0";
		$sqlr .= " and s.upd_date = r.upd_date";
		$sqlr .= " and s.upd_time = r.upd_time";
		$sqlr .= " and s.hostname = r.hostname";
		$sqlr .= " and s.catname = r.catname";
		$sqlr .= " order by s.upd_date, s.upd_time ";
	} else {
		$sqlr  = "select s2.upd_date, s2.upd_time, r.hostname, r.catname, r.inpath";
		$sqlr .= " from rtlist r,";
		$sqlr .= " (select min(s.upd_date) upd_date, min(s.upd_time) upd_time";
		$sqlr .= " from sumlist s";
		$sqlr .= " where upd_flg=1 ";
		$sqlr .= " and busy_flg=0) s2";
		$sqlr .= " where s2.upd_date = r.upd_date ";
		$sqlr .= " and s2.upd_time = r.upd_time ";
		$sqlr .= " order by s2.upd_date, s2.upd_time ";
	}

	$logger->warn("$sqlr");
	my $sthr = $hDB->prepare($sqlr);
	my $ret  = $sthr->execute();
	if ( !$ret ) {
		$logger=fatal("$hDB->errstr :$!\n");
		die;
	}

	# @rtlistに{/ホスト/カテゴリ/日付/時刻/ファイル名}の集計対象リストを作成
	my @rtlist;
	my $check = 'first';
	while ( my @res = $sthr->fetchrow_array ) {
		my ( $upd_date, $upd_time, $hostname, $catname, $inpath ) = @res;
		my $path = "/$hostname/$catname/$upd_date/$upd_time/$inpath";
		$logger->info("PATH : $path");
		# --onecycleオプション付きの場合は一巡目の処理で終了
		if ($ONECYCLE) {
			if ($check ne 'first') {
				last if ($check ne "$upd_date/$upd_time");
			}
		}
		$check = "$upd_date/$upd_time";

		push( @rtlist, $path );
	}
	$sthr->finish;
	undef($sthr);
	$hDB->disconnect;

	$logger->warn("SELECT [" . scalar( @rtlist ) . "]");
	return (@rtlist);
}

# 集計したファイルリストを履歴DBに更新済みとして登録する
# sumlist表に(hostname, catname, upd_date, upd_time)をキーにして集計済み
# フラグ(upd_flg=2)を立てる。
# 入力値：{ホスト|カテゴリ|日付|時刻} の配列
# 戻り値：なし

sub updsumlist {
	my (%rtlist) = @_;

	# ロック待ちエラー発生時にリトライする。
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

		# sumlist検索(dt, tm, host, cat, uflg, bflg)
		my $sqlr = "replace into sumlist values(?, ?, ?, ?, 2, 0)";

		$logger->warn("$sqlr");
		my $sthr = $hDB->prepare($sqlr);

		for my $key ( sort keys %rtlist ) {
			my ( $host, $cat, $upd_date, $upd_time ) = split( /\|/, $key );

			my $ret = $sthr->execute( $upd_date, $upd_time, $host, $cat );
			if ( !$ret ) {
				$logger->fatal("errstr : $!");
				die; 
			}
			$logger->info("[UPDATE][$host, $cat, $upd_date, $upd_time]");
		}
		$sthr->finish;
		$hDB->commit;
		undef($sthr);
		$hDB->disconnect;
	}
	return (1);
}

# ファイル履歴リストをDB登録
# sumhist_hourly, sumhist_dayly表に(hostname, catname, upd_date, upd_time,
# inpath)をキーにして集計成功件数(cnt_sum)を登録する。
# 入力値：{/ホスト/カテゴリ/日付/時刻/ファイル名}の配列
# 戻り値：なし

sub updsumhist {
	my (@infile) = @_;

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
	my $sqlr_sumhist_hourly  = "select cnt_rt, cnt_sum, cnt_sumng from sumhist_hourly";
	   $sqlr_sumhist_hourly .= " where upd_date=? and upd_time=?";
	   $sqlr_sumhist_hourly .= " and hostname=? and catname=? and inpath=?";
	my $sthr_sumhist_hourly  = $hDB->prepare($sqlr_sumhist_hourly);

	# sumhist履歴(dayly)検索SQL
	my $sqlr_sumhist_dayly  = "select cnt_rt, cnt_sum, cnt_sumng from sumhist_dayly";
	   $sqlr_sumhist_dayly .= " where upd_date=? ";
	   $sqlr_sumhist_dayly .= " and hostname=? and catname=? and inpath=?";
	my $sthr_sumhist_dayly  = $hDB->prepare($sqlr_sumhist_dayly);

	# sumlist履歴(hourly)登録SQL
	my $sqlc_sumhist_hourly = "replace into sumhist_hourly values(?, ?, ?, ?, ?, ?, ?, ?)";
	my $sthc_sumhist_hourly = $hDB->prepare($sqlc_sumhist_hourly);

	# sumlist履歴(dayly)登録SQL
	my $sqlc_sumhist_dayly = "replace into sumhist_dayly values(?, ?, ?, ?, ?, ?, ?)";
	my $sthc_sumhist_dayly = $hDB->prepare($sqlc_sumhist_dayly);

	for my $res(@infile) {
		# 先頭の"/"は除外する。
		my ($path, $retcode) = split(/\|/, $res);
		my @fld = split( /\//, $path );
		my ($hostname, $catname, $upd_date, $upd_time, @rtfiles) = split(/\//, $path);
		my $rtfile = join("/", @rtfiles);

		# 履歴テーブル(hourly)に登録
		$sthr_sumhist_hourly->execute($upd_date, $upd_time, $hostname, $catname, $rtfile);
		my ($cnt_rt, $cnt_sum, $cnt_sumng) = $sthr_sumhist_hourly->fetchrow_array;
		if ($retcode eq 'OK') {
			$cnt_sum ++;
		} else {
			$cnt_sumng ++;
		}
		my $ret = $sthc_sumhist_hourly->execute($upd_date, $upd_time, $hostname, $catname, $rtfile, $cnt_rt, $cnt_sum, $cnt_sumng);
		my $msg = "[REPLACE SUMLIST_HOURLY] $upd_date, $upd_time, $hostname, $catname, $rtfile, $cnt_rt, $cnt_sum, $cnt_sumng";
		if ( !$ret ) {
			$logger->error("$! : $msg");
		} else {
			$logger->info($msg);
		}

		# 履歴テーブル(dayly)に登録
		$sthr_sumhist_dayly->execute($upd_date, $hostname, $catname, $rtfile);
		my ($cnt_rt2, $cnt_sum2, $cnt_sumng2) = $sthr_sumhist_dayly->fetchrow_array;
		if ($retcode eq 'OK') {
			$cnt_sum2 ++;
		} else {
			$cnt_sumng2 ++;
		}
		my $ret2 = $sthc_sumhist_dayly->execute($upd_date, $hostname, $catname, $rtfile, $cnt_rt2, $cnt_sum2, $cnt_sumng2);
		my $msg2 = "[REPLACE SUMLIST_DAYLY] $upd_date, $hostname, $catname, $rtfile, $cnt_rt2, $cnt_sum2, $cnt_sumng2";
		if ( !$ret2 ) {
			$logger->error("$! : $msg2");
		} else {
			$logger->info($msg2);
		}
	}

	$sthr_sumhist_hourly->finish;
	$sthr_sumhist_dayly->finish;
	$sthc_sumhist_hourly->finish;
	$sthc_sumhist_dayly->finish;
	$hDB->commit;

	undef $sthr_sumhist_hourly;
	undef $sthr_sumhist_dayly;
	undef $sthc_sumhist_hourly;
	undef $sthc_sumhist_dayly;

	$hDB->disconnect;
}

# 集計処理ワーカー
# 入力：集計ファイルハンドラー,集計ID{順番/件数},集計キー
# 戻り値：なし

sub consumerSumcmd {
	my ($fh, $fh2, $consumerid, $sumlistkey) = @_;

	# イベント送信用データ
	my %senddat;

	# 集計キー{ホスト|カテゴリ|日付|時刻}を基に、集計対象ファイルを取得
	# 集計対象ファイルは"|"で区切られた複数件が対象
	for my $key(split(/\|/, $SUMLIST{$sumlistkey})) {

		# キーデータがない場合はループを抜ける
		next if ($SUMCMD{$key} eq 'NULL');
		next if ($key eq '');
		
		# コマンド実行
		my $t0 = [gettimeofday];
		$logger->info($SUMCMD{$key});
		my $exitcode = 0;

		# プリントオプション付きの場合はヘッダ情報出力
		print("\n# $key\n") if ($PRINT);

		# コマンドは";"で区切られた複数件が対象
		for my $cmd (split( ";", $SUMCMD{$key} )) {

			# .plファイルであれば前にperl ～をつける
			if ( $cmd =~ /^\s*(.*?\.pl)(.*)$/ ) {
				my ($sc, $arg) = ($1, $2);

				# 相対パスの場合は、$PWDを追加
				$sc = "$PWD/$sc" if ($sc !~ /^\//);

				# デフォルトオプション (--idir, --odir, --ifile) が指定されていない
				# 場合のみ追加指定する。
				my $opt;
				$opt .= "--ifile=$ENV_IFILE{$key} " if ($cmd !~ /--ifile/);
				$opt .= "--idir=$ENV_IDIR{$key} "   if ($cmd !~ /--idir/);
				$opt .= "--odir=$ENV_ODIR{$key} "   if ($cmd !~ /--odir/);

				$cmd = "$Param::CMD_PERL $sc $arg $opt";
			}

			# プリントオプション付の場合はコマンドを標準出力
			if ($PRINT) {
				print("$cmd\n");
			} else {
			# プリントオプションが付かない場合はコマンド実行
				$logger->info("[$$][$consumerid] $cmd");
				my ($rc, $obuf, $ebuf) = spawn2($cmd);

				# 1つでも異常終了していたら、その値を終了コードにセットする
				$exitcode = $rc if ($rc != 0 && $exitcode == 0);

				# 出力結果から aaa=bbb の行を抽出して、%senddat に登録
				# 集計キー{ホスト/カテゴリ/日付/時刻/ファイル@パラメータ}
				my @lines = split(/\n/, $obuf);
				next if (scalar(@lines) == 0);
				for my $line( @lines ) {
					next if ($line!~/^(\w.*)\s*=\s*(.*)$/);
					my ($param, $val) = ($1, $2);
					my $sendkey = $key . '@' . $param;
					$senddat{$sendkey} = $val;
				}
			}

		}

		# 終了コードと処理時間をログ出力
		my $elapsed = tv_interval ($t0); 
		my $msg = sprintf("[%s][%d][%5.2f] %s", 
			$consumerid, $exitcode, $elapsed, $key);
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

			$logger->info("[$$][RES] $key,$exitcode");
			print $cfh "$key,$exitcode\n";

			flock $cfh, 0;
			close($cfh);
		}
	}

	# 送信イベントを送信
	if (!$PRINT) {
		# 出力を排他制御するため，ファイル名で開き直す
		my $cfh;
		open $cfh, '>>', $fh2->filename or die $!;

		# ファイルの排他制御
		flock $cfh, 2 or die $!;
		seek $cfh, 0, 1;

		for my $sendkey (sort keys %senddat) {
			my $h = $sendkey . '=' . $senddat{$sendkey};
			$logger->info("[Send JMS] $h");
			print $cfh $h . "\n";
		}

		flock $cfh, 0;
		close($cfh);
	}
}

# YYYYMMDD_HHMISS形式でカレント時刻を取得する
# 戻り値：日時
sub datetime {
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
	my $dt = sprintf("%04d%02d%02d_%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
	return($dt);
}

sub main {
	my $cmd;

	lock("$WORK/lk_sumlog");    # 排他制御

	# 更新日チェック
	$logger->warn("================= Check Perf Log File ===================");
	my $t0 = [gettimeofday];

	my @INFILES;

	# 全ファイル検索
	if ($RESET) {
		@INFILES = getsumlist_file();
	# ディレクトリ指定検索
	} elsif ($IDIR) {

		# 相対パスで指定している場合は、~/perfstat/analysis の下のパスに変換する。
		if (-d $IDIR) {
			$IDIR = File::Spec->rel2abs($IDIR);
			$IDIR =~s/.*analysis\///g;
		}
		
		$IDIR =~ s/^\///g;    # 先頭の"/"を取り除く
		my $cmd = "(cd $LOGDIR; $Param::CMD_FIND $IDIR -name \"*.*\")";
		$logger->debug($cmd);
		if (!open( IN, "$cmd|" )) {
			$logger->fatal("Can't open file $cmd : $!");
			die;
		}
		while (<IN>) {
			chop($_);
			$_ =~ s/^\.\///g;     # 先頭の"./"を取り除く
			push( @INFILES, $_ );
		}
		close(IN);
	# 前回更新履歴DBからファイルを検索
	} else {
		@INFILES = getsumlist();
	}

	$logger->warn("GREP  : [ $GREP ]")  if ($GREP);

	# 対象ファイルを集計
	for my $path (sort @INFILES) {
		# キーワードでヒットしないファイルは省略
		if ($GREP) {
			my $idx = index( $path, $GREP );
			next if ( $idx == -1 );
		}

		# 整形コマンド実行
		cksumcmd($path);
	}

	# 対象ファイルがない場合は終了
	if ( scalar(%SUMCMD) == 0 ) {
		$logger->warn("END : No restore file");
		exit(99);
	}

	# 出力先ディレクトリ作成
	$logger->warn("================= Make Summary Directory ====================");
	my %mdpath;
	# ODIRキー配列からディレクトリ作成対象リストを作成
	for my $key(keys %ENV_ODIR) {
		$mdpath{$ENV_ODIR{$key}} = 1;
	}
	my $cntn = 0;
	my $cnts = 0;
	for my $path(sort keys %mdpath) {
		$cntn ++;
		$logger->info("[MKDIR] $path");
		mkdir_p($path);
		$cnts ++ if (-d $path);
	}
	$logger->warn("[MKDIR][RES] target=$cntn, sucsess=$cnts");

	# 集計コマンド実行
	$logger->warn("================== Execute Summary Command ==================");

	# 集計結果データファイルスクリプター
	my $fh = new File::Temp(UNLINK => 0);
	$logger->info("tmp file1: $fh->filename");

	# ZABBIX結果データファイルスクリプター
	my $fh2 = new File::Temp(UNLINK => 0);
	$logger->info("tmp file2: $fh2->filename");

	# 集計リストキューイング
	my $active = 0;
	my $cnt = 0;
	my $ncnt = scalar(keys %SUMLIST);
	for my $key ( sort keys %SUMLIST ) {
		$cnt++;
		my $seq = sprintf("%d/%d", $cnt, $ncnt);

		# ワーカープロセス起動
		unless (fork()) {
			# ワーカプロセスの処理
			consumerSumcmd($fh, $fh2, $seq, $key);
			exit;
		}

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

	# 残りのワーカプロセスのデータ処理
	while (my ($child) = wait3(1)) {
		$logger->warn("[EXIT2] pid=$child");
	}

	# 更新履歴DB登録
	$logger->warn("================= Update Summary Log DB =====================");
	# ファイルハンドルをつかんでいるので消しても問題なし
	unlink $fh->filename;

	# コマンド実行結果集計
	my @outfiles = ();
	my %rtlist = ();
	while (<$fh>) {
		chop;
		# {ファイルパス名,終了コード}を解析
		my ($fn, $rc) = split(",", $_);

		# 成功したコマンドはファイル名|0とし、失敗したコマンドはファイル名|1として登録する
		if ($rc == 0) {
			push(@outfiles, join("|", ($fn, 'OK')));
		} else {
			push(@outfiles, join("|", ($fn, 'NG')));
		}
		# ファイルパスを{ホスト名|カテゴリ|日付|時刻}に分解
		my @fld = split( /\//, $fn );
		my $key = join( "|", @fld[ 0 .. 3 ] );
		$rtlist{$key} = 1;
	}

	# DB登録
	if (!$PRINT) {
		updsumlist(%rtlist) if (!$NOUPDATE);
		updsumhist(@outfiles);
	}

	# 更新履歴DB登録
	$logger->warn("================= Update Event Log DB ======================");
	# ファイルハンドルをつかんでいるので消しても問題なし
	unlink $fh2->filename;

	# コマンド実行結果集計
	# {ホスト名, 項目名}をキーに値を登録する。
	my %ev = ();
	while (<$fh2>) {
		chop;
		next if ($_!~/^(.*?)\/.*@(.*?)=(.*)/);
		my ($host, $param, $val) = ($1, $2, $3);
		$ev{$host . "|" . $param} = $val;
	}

	# zabbix_sender実行パラメータチェック
	my ($zbxhost, $zbxport);
	if ($ZABBIXSERVER=~/^(.+?):(\d+?)$/) {
		($zbxhost, $zbxport) = ($1, $2);
	} else {
		$logger->warn("Can't Read ZABBIXSERVER(Param.pm): $ZABBIXSERVER");
	}

	# ZABBIX 送信データ作成
	my $zbuf;
	for my $key(sort keys %ev) {
		my $val = $ev{$key};
		my ($host, $param) = split(/\|/, $key);
		# <zabbix_server> <hostname> <port> <key> <value>
		$zbuf .= "$zbxhost $host $zbxport $param $val\n";
		$logger->warn("[ZBX Send] $host, $param, $val");
	}

	# ZABBIX データ送信
	if ( !-f $CMD_ZBXSEND ) {
		$logger->warn("Can't find \$CMD_ZBXSEND in Param.pm : Ignore");
	} else {
		my $loadfile = tempfile('tsv');
		io($loadfile)->print($zbuf);

		# タイムアウト監視をしてコマンド起動
		my $timeout = 0;

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
#				select(undef, undef, undef, 0.25); 

			};
			alarm 0;
			my $res = $@;
			# 例外処理(タイムアウトのチェック)
			if ($res=~/timeout/) {
				$logger -> warn("[TIMEOUT] Skip zabbix_sender.");
				$timeout = 1;
			}
		}
		unlink($loadfile);
	}

	my $elapsed = tv_interval ($t0); 
	$logger->warn("Total Elapse = $elapsed");
	$logger->warn("=========================== End =============================");

	unlink("$WORK/lk_sumlog");    # 排他制御解除
}
