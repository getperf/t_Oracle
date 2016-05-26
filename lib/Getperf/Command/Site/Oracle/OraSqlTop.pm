package Getperf::Command::Site::Oracle::OraSqlTop;
use strict;
use warnings;
use Data::Dumper;
use Time::Piece;
use base qw(Getperf::Container);
use Getperf::Command::Master::Oracle;

sub new {bless{},+shift}

sub parse {
    my ($self, $data_info) = @_;

	my (%results, %cpu_stats);
	my $step = 3600;
	my $n_top = 40;
	my @headers = qw/executions disk_reads buffer_gets rows_processed cpu_time elapsed_time/;

	$data_info->step($step);
	$data_info->is_remote(1);
	my $instance = $data_info->file_suffix;
	my $sec  = $data_info->start_time_sec->epoch;
	if (!$sec) {
		return;
	}

	open( my $in, $data_info->input_file ) || die "@!";
	while (my $line = <$in>) {
		$line=~s/(\r|\n)*//g;			# trim return code
		if ($line=~/Date:(.*)/) {		# parse time: 16/05/23 14:56:52
			$sec = localtime(Time::Piece->strptime($1, '%y/%m/%d %H:%M:%S'))->epoch;
			next;
		}
		my ($timestamp, $sql_hash, @values) = split(/\s*\|\s*/, $line);
		next if (!defined($timestamp) || $timestamp eq 'TIME');
		$results{$sql_hash}{$sec} = join(' ', @values[0..5]);
		$cpu_stats{$sql_hash} = $values[4];
	}
	close($in);

	my $rank = 1;
	for my $sql_hash(sort {$cpu_stats{$b} <=> $cpu_stats{$a}} keys %cpu_stats) {
		$data_info->regist_device($instance, 'Oracle', 'ora_sql_top', $sql_hash, undef, \@headers);
		my $output = "Oracle/${instance}/device/ora_sql_top__${sql_hash}.txt";
		$data_info->simple_report($output, $results{$sql_hash}, \@headers);
		$rank ++;
		last if ($n_top < $rank);
	}

	return 1;
}

1;
