package Getperf::Command::Site::Oracle::OraSesg;
use strict;
use warnings;
use Data::Dumper;
use Time::Piece;
use base qw(Getperf::Container);
use Getperf::Command::Master::Oracle;

sub new {bless{},+shift}

sub parse {
    my ($self, $data_info) = @_;

	my (%results);
	my $step = 600;
	my @headers = qw/count/;

	$data_info->step($step);
	$data_info->is_remote(1);
	my $instance = $data_info->file_suffix;
	my $sec  = $data_info->start_time_sec->epoch;
	if (!$sec) {
		return;
	}

	open( my $in, $data_info->input_file ) || die "@!";
	my $row = 0;
	while (my $line = <$in>) {
		$row ++;
		if ($row <= 3) {
			next;
		}
		$line=~s/(\r|\n)*//g;			# trim return code
		my ($tms, $inst, $status, $count) = split(/\s*\|\s*/, $line);
		print "$row:($tms, $inst, $status, $count)\n";
		$sec = localtime(Time::Piece->strptime($tms, '%Y/%m/%d %H:%M:%S'))->epoch;
		$results{$inst}->{$status}->{$sec} = $count;
		$results{'_global'}->{$status}->{$sec} = $count;
		# $zabbix_send_data{$sec}{$zabbix_item} = $values[2];
	}
	close($in);
	# print Dumper \%results;
	for my $inst(keys %results) {
		for my $status (keys %{$results{$inst}}) {
			my $instance = "instance${inst}";
			$data_info->regist_device($instance, 'Oracle', 'ora_sesg', $status, undef, \@headers);
			my $output = "Oracle/${instance}/device/ora_sesg__${status}.txt";	# Remote collection
			$data_info->simple_report($output, $results{$inst}->{$status}, \@headers);
		}
	}

	return 1;
}

1;
