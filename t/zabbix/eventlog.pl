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
use Getopt::Long;
use File::Basename;
use DBI;
use Log::Log4perl;
use File::Temp;
use IO::All;
use Net::Stomp;
use English;

use Param;

# 環境変数設定
$ENV{'LANG'}   = 'C';
my ($USERNAME) = getpwuid($UID);

# ディレクトリ設定
chop(my $HOST = `hostname`);
chop(my $PWD = `dirname $0`);             # ~mon/script
$PWD = File::Spec->rel2abs($PWD);
my $WORK   = "$PWD/../_wk";         # ~mon/_wk
my $WKLOG  = "$PWD/../_log";        # ~mon/_log
my $LOGDIR = "$PWD/../analysis";    # ~mon/analysis
my $SUMDIR = "$PWD/../summary";     # ~mon/summary
my $BINDIR = sprintf("%s/zabbix/sbin", $ENV{'HOME'});
                                    # ~/zabbix/sbin

# 実行オプションチェック
my $EVENTSERVER  = $Param::EVENTSERVER  || 'localhost:61613';
my $ZABBIXSERVER = $Param::ZABBIXSERVER || 'localhost:10051';

# 設定ファイルに定義したloggerを生成
Log::Log4perl::init("$PWD/log4perl.conf");
my $logger = Log::Log4perl::get_logger("pslog");

# ZABBIX環境チェック
my $CMD_ZBXSEND = $Param::CMD_ZBXSEND;
if ( !-f $CMD_ZBXSEND ) {
	$logger->fatal("Can't find \$CMD_ZBXSEND in Param.pm : $CMD_ZBXSEND");
	die;
}

main();
exit(0);

# 排他制御：2重起動となった場合は強制終了する。
# 戻り値：なし

sub lock {
    my ($lockfile) = @_;

    if ( my $pid = readlink($lockfile) ) {
        # "ps -ef"の2列目の値をチェックする。
        if ( grep ( /^\s*(\S+)\s+$pid\s+/, `ps -ef` ) ) {
            $logger -> error("$0 Another Process Running : PID = $$");
            die;
        } else {
            unlink($lockfile);
            symlink( $$, $lockfile );
        }
    } else {
        if ( !symlink( $$, $lockfile ) ) {
            $logger -> error("$0 Still Running : PID = $$");
            die;
        }
    }
}

# ワークディレクトリにテンポラリファイルを作成する
# 戻り値：ファイル名
sub tempfile {
    my ($sfx) = @_;

    my $fh = File::Temp->new(
        UNLINK => 1,
        DIR => $WORK,
        TEMPLATE => 'XXXXXXXX',
        SUFFIX   => ".$sfx",
    ) || die "Can't open : $OS_ERROR";
    close($fh);

    return($fh->filename);
}

# コマンドを起動し、STDOUT,STDERRにログ出力する
# 第2引数で異常終了時のアクションを決める('stop', 'ignore')
# 戻り値：終了コード
sub spawn {
	my ($cmd, $cond) = @_;

	# 標準出力、エラー出力ハンドラー
	my $shell = tempfile("sh");
	my $ofile = tempfile("out");
	my $efile = tempfile("err");

	# コマンド実行 : "command 1>file1 2>file2"
	io($shell) -> println($cmd);
	my $syscmd = "sh " . $shell . " 1> " . $ofile . " 2> " . $efile;
	$logger -> debug($syscmd);
	my $ret = system($syscmd);

	# STDOUT, STDERR をログ出力
	my $obuf = io($ofile) -> all;
	my $ebuf = io($efile) -> all;

	$logger -> warn(  "$cmd [$ret]\n$obuf" ) if ( $obuf );
	$logger -> error( "$cmd [$ret]\n$ebuf" ) if ( $ebuf );

	unlink($shell);
	unlink($ofile);
	unlink($efile);

	# 終了コードが0以外の場合は$condでアクションを決める
	if ($ret) {
		die if ($cond eq 'stop');
	}

	return($ret);
}

# メイン
sub main {
	$logger->warn("======================== BEGIN ========================");
	lock("$WORK/lk_event");		# 排他制御

	# 集計バッファ
	my %buf;

	# 1時間前の時刻"YYYYMMDD HHMI"を取得する(1時間前のイベントは取り除く為)
	my $mtime = time() - 24*3600;
	my ($ss, $mm, $hh, $DD, $MM, $YY, $wday, $yday, $isdst) = localtime($mtime);
	my $lastdt = sprintf("%04d%02d%02d %02d%02d", 
		$YY + 1900, $MM + 1, $DD, $hh, $mm);

	# JMS キュー読込 : sumlog.ユーザ名
	# 集計結果の変換 : "ホスト/カテゴリ/日/時/ファイル名@キー=値" から、
	# "{ホスト キー}=値" に変換
	# yiha01b/HW/20090518/1215/Sar_u_SunOS.txt@cpu_idle=97.1774193548387
	my $qname = 'sumlog.' . $USERNAME;
	my @msgs = getjms($qname);
	$logger -> warn( "[Check] $qname " . scalar(@msgs));
	for my $line(@msgs) {
		next if ($line!~/^(.*?)@(.*?)=(.*)$/);
		my ($opath, $item, $val) = ($1, $2, $3);
		my ($host, $cat, $dt, $tm, $fname) = split(/\//, $opath);
		if ($lastdt lt "$dt $tm") {
			my $key    = $host . ' ' . $item;
			$buf{$key} = $val;
		} else {
			$logger -> error( "Time NG [$lastdt, $dt $tm] $line");
		}
	}

	# JMS キュー読込 : forecast.ユーザ名
	# 予測結果の変換 : "日時,RRDパス,DS,値" から、
	# "{ホスト キー}=値 に変換
	# 2009/04/22 21:31:32,valtest03/HW/sar_u.rrd,idle,0
	my $qname = 'forecast.' . $USERNAME;
	my @msgs = getjms($qname);
	$logger -> warn( "[Check] $qname " . scalar(@msgs));
	for my $line(@msgs) {
		my ($dt, $rrd1, $ds, $val) = split(/,/, $line);

		# 日付チェック
		next if ($dt!~/(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)/);
		my ($YY, $MM, $DD, $hh, $mm, $ss) = ($1, $2, $3, $4, $5, $6);
		my $tms = sprintf("%04d%02d%02d %02d%02d", $YY, $MM, $DD, $hh,$mm);

		# rrdファイルチェック
		my @arr  = split(/\//, $rrd1);
		my $host = shift(@arr);
		my $cat  = lc(shift(@arr));
		my $rrd2 = join("_", @arr);
		next if ($rrd2!~/(.*)\.rrd?/);

		# {カテゴリ}.{rrdパス}_{ds} (hw.sar_u_idle_failure) に変換
		if ($lastdt lt $tms) {
			my $item = sprintf("%s.%s_%s_failure", $cat, $1, $ds);
			my $key    = "$host $item";
			$buf{$key} = $val;
		} else {
			$logger -> error( "Time NG [$lastdt, $tms] $line");
		}
	}

	# zabbix_senderコマンド実行
	my ($zbxhost, $zbxport);
	if ($ZABBIXSERVER=~/^(.+?):(\d+?)$/) {
		($zbxhost, $zbxport) = ($1, $2);
	} else {
		die "Can't Read ZABBIXSERVER(Param.pm): $ZABBIXSERVER";
	}
	

	# _wk下にロードファイル生成
	my $tsvbuf;
	for my $key(sort keys %buf) {
		my $val = $buf{$key};
		my ($host, $key) = split(/ /, $key);
		$logger->warn("[ZBX] <$host> <$key> <$val>");
		# <zabbix_server> <hostname> <port> <key> <value>
		$tsvbuf .= "$zbxhost $host $zbxport $key $val\n";
	}
	my $loadfile = tempfile('tsv');
	io($loadfile)->print($tsvbuf);

	$logger -> debug("[ZABBIX DAT]\n" . $tsvbuf);

#	my $cmd = "$CMD_ZBXSEND -vv -z $zbxhost -p $zbxport -i $loadfile";
	my $cmd = "$CMD_ZBXSEND -vv -i $loadfile";
	$logger -> warn("[EXEC]\n$cmd");
#	spawn($cmd);
	unlink($loadfile);

	$logger->warn("========================= END =========================");
	unlink("$WORK/lk_monitor");    # 排他制御解除
}

# 引数で指定したキュー名のデータを取得して結果配列を返す
sub getjms {
	my ($qname) = @_;

	# ActiveMQ接続
	my ($jmshost, $jmsport);
	if ($EVENTSERVER=~/^(.+?):(\d+?)$/) {
		($jmshost, $jmsport) = ($1, $2);
	} else {
		die "Can't Read EVENTSERVER(Param.pm): $EVENTSERVER";
	}
	my $stomp = Net::Stomp->new({
		hostname    => $jmshost,
		port        => $jmsport }
	);

	$stomp->connect();
	$stomp->subscribe({
		destination => "/queue/$qname",
		ack         => 'client',
		'activemq.prefetchSize' => 1
	});

	#キュー読み込み
	my @msgs;
	while($stomp->can_read({ timeout => '1' })) {
		my $frame = $stomp->receive_frame;
		push(@msgs, $frame->body);
		$stomp->ack( { frame => $frame } );
	}
	$stomp->disconnect;

	return(@msgs);
}
