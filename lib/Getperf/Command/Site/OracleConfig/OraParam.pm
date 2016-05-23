package Getperf::Command::Site::OracleConfig::OraParam;
use strict;
use warnings;
use Data::Dumper;
use Time::Piece;
use base qw(Getperf::Container);
use Getperf::Command::Master::OracleConfig;

sub new {bless{},+shift}

sub parse {
    my ($self, $data_info) = @_;

	my %infos;
	my $host = $data_info->host;
	my $osname = $data_info->get_domain_osname();
	open( my $in, $data_info->input_file ) || die "@!";
	while (my $line = <$in>) {
		$line=~s/(\r|\n)*//g;			# trim return code
		if ($line=~/Date:(.*)/) {		# parse time: 16/05/23 14:56:52
			my $sec = localtime(Time::Piece->strptime($1, '%y/%m/%d %H:%M:%S'))->epoch;
			next;
		}
		my ($name, $value) = split(/\s*\|\s*/, $line);
		next if (!defined($name) || $name eq 'NAME');
		$infos{$name} = $value;
	}
	close($in);

	my $dump_dest = $infos{background_dump_dest};
	my $db_name   = $infos{db_name};
	my $alert_log = "${dump_dest}/alert_${db_name}.log";
	my $info_file = "info/oracle_log__${db_name}";
	my %stats = ();
	$stats{ora_alert_log}{$db_name} = $alert_log;
	$data_info->regist_node($host, $osname, $info_file, \%stats);
	return 1;
}

1;
