package Getperf::Command::Site::Oracle::OraSqlTop;
use strict;
use warnings;
use Data::Dumper;
use Time::Piece;
use base qw(Getperf::Container);
use Getperf::Command::Master::Oracle;
use Getperf::Command::Site::Oracle::Base::CactiDB qw/update_cacti_graph_item/;
sub new {bless{},+shift}

sub parse {
    my ($self, $data_info) = @_;

	my (%results, %sql_stats);
	my $step = 3600;
	my $n_top = 40;
	my @headers = qw/executions disk_reads buffer_gets rows_processed cpu_time elapsed_time/;
	my %graph_headers = (
		"cpu_time"    => "SQL CPU Time Ranking",
		"buffer_gets" => "SQL Buffer Get Ranking",
		"disk_reads"  => "SQL Disk Read Ranking",
	);

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
		my $col = 0;
		map {
			my $header = $headers[$col];
			$results{$sql_hash}{$sec}{$header} = $_;
			$sql_stats{$sql_hash}{$header}    += $_;
			$col ++;
		} @values[0..5];
	}
	close($in);

	my $query_items =
		"SELECT  g.local_graph_id, gi.sequence, " .
		"    gi.id graph_templates_item_id, gi.text_format, " .
		"    dd.id data_template_data_id, dd.data_source_path " .
		"FROM graph_templates_graph g, " .
		"    graph_templates_item gi, " .
		"    data_template_rrd dr USE INDEX (local_data_id), " .
		"    data_template_data dd " .
		"WHERE gi.local_graph_id = g.local_graph_id " .
		"    AND gi.task_item_id = dr.id " .
		"    AND dr.local_data_id = dd.local_data_id " .
		"    AND gi.graph_type_id in (4) " .
		"    AND g.title_cache = '__graph_title__' " .
		"ORDER BY gi.sequence";

	for my $sort_key(qw/cpu_time buffer_gets disk_reads/) {
		my @sql_ranks = sort { $sql_stats{$b}{$sort_key} <=> $sql_stats{$a}{$sort_key} } keys %sql_stats;
		my $rank = 1;
		for my $sql_hash(@sql_ranks) {
			$data_info->regist_device($instance, 'Oracle', 'ora_sql_top', $sql_hash, undef, \@headers);
			my $output = "Oracle/${instance}/device/ora_sql_top__${sql_hash}.txt";
			$data_info->pivot_report($output, $results{$sql_hash}, \@headers);
			$rank ++;
			last if ($n_top < $rank);
		}
		$rank = 1;
		my $graph_header = $graph_headers{$sort_key};
		for my $graph_title_suffix('', ' - 2', ' - 3', ' - 4') {
			my $graph_title = "Oracle - ${instance} - " . $graph_header . $graph_title_suffix;
			my $query = $query_items;
			$query=~s/__graph_title__/${graph_title}/g;
			if (my $rows = $data_info->cacti_db_query($query)) {
				for my $row(@$rows) {
					my $graph_templates_item_id = $row->[2] || 0;
					my $data_template_data_id   = $row->[4] || 0;
					my $sql_hash = shift(@sql_ranks);
					if ($sql_hash && $graph_templates_item_id && $data_template_data_id) {
						my $rra = "<path_rra>/Oracle/${instance}/device/ora_sql_top__${sql_hash}.rrd";
						update_cacti_graph_item($data_info, $sql_hash, $graph_templates_item_id,
						                        $data_template_data_id, $rra);
					} else {
						my $rra = "<path_rra>/Oracle/${instance}/device/ora_sql_top__dummy.rrd";
						update_cacti_graph_item($data_info,, 'unkown', $graph_templates_item_id,
						                        $data_template_data_id, $rra);
					}
				}
			}
		}
	}

	return 1;
}

1;
