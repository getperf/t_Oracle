#!/usr/local/bin/perl
use strict;
# MySQLのCactiリポジトリのグラフタイトルと凡例を更新する。

# パッケージ読込
BEGIN { 
    my $pwd = `dirname $0`; chop($pwd);
    push(@INC, "$pwd/libs", "$pwd/"); 
}
use DBI;
use Data::Dumper;
use Time::Local;
use Getopt::Long;
use Param;

# MySQL設定
my $DS   = 'DBI:mysql:pnyok03;host=localhost';
my $USER = 'pnyok03';
my $PASS = 'pnyok03';

# 環境変数設定
$ENV{'LANG'}='C';
$ENV{'LD_LIBRARY_PATH'}='/usr/lib:/usr/openwin/lib:/usr/dt/lib:/usr/local/lib:/usr/local/lib/sparcv9';
my $LOADFILE = 'updCactiItem.txt';
my %LOADDAT;
my $DB;

# 実行オプション処理
my $ODIR = $ENV{'PS_ODIR'} || '.';
my $IDIR = $ENV{'PS_IDIR'} || '.';
my $IFILE = $ENV{'PS_IFILE'} || 'psutil.txt';

GetOptions (
	'--idir=s'     => \$IDIR,
	'--ifile=s'    => \$IFILE,
	'--odir=s'     => \$ODIR,
	'--file=s'     => \$LOADFILE,
  ) || die "USAGE: $0 --file=loadfile\n";

# メイン
&main;
exit(0);

# CSVファイルを読込み
# $LOADDAT{'aaa'} = 99,99,...に格納
sub readfile {
  open(IN, $LOADFILE) || die "Can't open $LOADFILE : $!";
  my ($tname, @ids);
  while (<IN>) {
    chop;
    # CSV形式の $_ から値を取り出して @arr に入れる
    my $tmp = $_;
    $tmp =~ s/(?:\x0D\x0A|[\x0D\x0A])?$/,/;
    my @arr = map {/^"(.*)"$/ ? scalar($_ = $1, s/""/"/g, $_) : $_}
      ($tmp =~ /("[^"]*(?:""[^"]*)*"|[^,]*),/g);

    die "Read Error : $tmp\n" if (scalar(@arr) != 2);

    # %LOADFILE に値を格納
    $tname = $arr[0];
    if ($LOADDAT{$tname}) {
      $LOADDAT{$tname} .= "," . $arr[1];
    } else {
      $LOADDAT{$tname} = $arr[1];
    } 
  }
  close(IN);
}

# CactiリポジトリからグラフIDと項目IDを取得
# 入力：タイトル名
sub getid {
  my ($title) = @_;
  
  # $title をキーにグラフIDと項目IDを取得する select 文作成
  my $sql = join(" ", qw (
    SELECT g.local_graph_id, gi.sequence 
    FROM graph_templates_graph g,
      graph_templates_item gi
    WHERE gi.local_graph_id = g.local_graph_id
      AND gi.graph_type_id in (7, 8)
      AND g.title_cache = __title__
    ORDER BY gi.sequence;
  ));
  $sql=~s/__title__/'$title'/g;

  warn "[GET] $sql\n";
  # SQL実行
  my $sth;
  $sth = $DB->prepare($sql);
  $sth->execute;

  # 実行結果を整形
  my $buf;
  my $num_rows = $sth->rows;
  if ($num_rows == 10) {
    for (my $i = 0; $i < $num_rows; $i++) {
      my @a = $sth->fetchrow_array;
      $buf .= join(",", @a) . "\n";
    }
  } else {
    warn("[GET] Not return 10 rows\n");
  }

  $sth->finish;

  return $buf;
}

# Cactiリポジトリからグラフの凡例を更新
# 入力：キー(グラフID, 項目ID)、凡例名
sub updtitle {
  my ($ids, $tnames) = @_;

  # 凡例名とキーを配列に分解してUPDATE文実行
  my @tname = split(/,/, $tnames);
  for my $line(split(/\n/, $ids)) {
    my ($gid, $item) = split(/,/, $line);
    my $title = shift(@tname);
    
    warn("[UPD] $gid,$item,$title\n");
    my $sql;
    $sql  = "update graph_templates_item set text_format = '$title' ";
    $sql .= "where local_graph_id = $gid ";
    $sql .= "and sequence = $item;";

    warn "[UPD] $sql\n";
    my $sth;
    $sth = $DB->prepare($sql);
    $sth->execute;
    $sth->finish;
  }
}

sub main {
  # ロードファイル読込み
  readfile();

  # MySQL接続
  $DB = DBI->connect($DS, $USER, $PASS) 
    || die "Got error $DBI::errstr when connecting to $DS\n";

  # タイトルで検索したグラフの凡例を更新する
  for my $title(sort keys %LOADDAT) {
    # グラフID,項目ID取得
    my $tmp = $title;
    $tmp=~s/ by / - by /g;
    warn("[Check title] $tmp\n");
    my $res = getid($tmp);
    # 凡例更新
    warn("[ERR] No data\n") if (!$res);
    updtitle($res, $LOADDAT{$title});
  }
  
  # MySQL切断
  $DB->disconnect;
}

