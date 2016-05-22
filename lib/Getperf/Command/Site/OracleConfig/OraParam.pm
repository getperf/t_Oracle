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

	my %results;
	my $step = 5;
#	my @headers = qw/col1 col2 col3/;

	$data_info->step($step);
	my $host = $data_info->host;

	my $osname = $data_info->get_domain_osname();
	print $osname . "\n";

#　In the case of remote collection, set is_remote to 1.
#	$data_info->is_remote(1);
#	my $host   = $data_info->postfix;

	my $sec  = $data_info->start_time_sec->epoch;
	if (!$sec) {
		return;
	}
	open( my $in, $data_info->input_file ) || die "@!";
#	$data_info->skip_header( $in );
	while (my $line = <$in>) {
		$line=~s/(\r|\n)*//g;			# trim return code
		# print $line . "\n";
		$results{$sec} = $line;
		$sec += $step;
	}
	close($in);
#	$data_info->regist_metric($host, 'OracleConfig', 'ora_param', \@headers);

	my $output = "ora_param.txt";						# Local collection
#	my $output = "OracleConfig/${host}/ora_param.txt";	# Remote collection

#	$data_info->simple_report('ora_param.txt', \%results, \@headers);
	return 1;
}

1;
