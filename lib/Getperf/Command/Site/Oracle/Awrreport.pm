package Getperf::Command::Site::Oracle::Awrreport;
use strict;
use warnings;
use Data::Dumper;
use Time::Piece;
use Time::Local;
use base qw(Getperf::Container);
use Getperf::Command::Site::Oracle::AwrreportHeader;

sub new {bless{},+shift}

our $headers = get_headers();
our $months  = get_months();

sub parse_loadprof {
	my ($str) = @_;
	my %loadprof = ();
	for my $key(keys %{$headers->{load_profiles}}) {
		my $keyword = $headers->{load_profiles}{$key};
		if ($str=~/$keyword(.*?):(.*)$/) {
			my @vals = split(' ', $2);
			my $val = shift(@vals);
			$val=~s/,//g;
			$loadprof{$key} = $val;
		} else {
			$loadprof{$key} = 0;
		}
	}
	return %loadprof;
}

sub parse_hit {
	my ($str) = @_;

	my %hit = ();
	for my $key(keys %{$headers->{hits}}) {
		my $keyword = $headers->{hits}{$key};
		if ($str=~/$keyword(.*?):(.*)$/) {
			my @vals = split(' ', $2);
			$hit{$key} = shift(@vals);
		} else {
			$hit{$key} = 0;
		}
	}
	return %hit;
}

sub parse_global_cache {
    my ($str) = @_;

    my %global_cache = ();
    if ($str=~/Estd Interconnect traffic .* ([\d|\.]+)/) {
        $global_cache{'traffic'} = $1;
    }
    return %global_cache;
}

sub parse_interconnect_ping {
    my ($lines) = @_;
    my %interconnect_ping = ();
    # if ($str=~/Estd Interconnect traffic .* ([\d|\.]+)/) {
    #     $interconnect_ping{'interconnect_traffic'} = $1;
    # }
    for my $line(@{$lines}) {
        if ($line =~/^\s*([\d\.\s]+)$/){
            my @arr = split(' ',$line);
            if (scalar(@arr) == 7) {
                # print Dumper \@arr;
                $interconnect_ping{$arr[0]} = $arr[5];
            }
            # print "LINE:$line\n";
        }
    }
    return %interconnect_ping;
}


sub norm {
    my ($value) = @_;

    my $unit = '';
    if ($value=~/^(.+)([K|M|G])/) {
        $value = $1;
        $unit = $2;
    }
    if ($unit eq 'K') {
        $value *= 1000 ;
    } elsif ($unit eq 'M') {
        $value *= 1000 * 1000;
    } elsif ($unit eq 'G') {
        $value *= 1000 * 1000 * 1000;
    }

    return $value;
}

sub parse_event {
    my ($str, $bg_event_str) = @_;

    my %event = ();
    for my $key(keys %{$headers->{events}}) {
        my $keyword = $headers->{events}{$key};
        if ($str=~/$keyword\s+(\d.*)$/) {
            my $val_str = $1;
            $val_str=~s/,//g;
            my @vals = split(/\s+/, $val_str);
            if ($keyword eq 'DB CPU') {
                $event{$key} = norm(shift(@vals));
            } else {
                my $val = norm($vals[1]);
                $event{$key} += $val;
            }
        } else {
            $event{$key} = 0;
        }
    }

    for my $key(keys %{$headers->{events}}) {
        my $keyword = $headers->{events}{$key};
        if ($bg_event_str=~/($keyword)\s+(\d.*)$/) {
            my $item = $1;
            my @vals = split(/\s+/, $2);
            my $val = undef;
            if ($key eq 'CPUTime' || $key eq 'DB CPU') {
                $val = shift(@vals);
            } else {
                $val = $vals[2];
            } 
            if (defined($val)) {
                $val=~s/,//g;
                $event{$key} += $val;
            }
        }
    }
    return %event;
}

sub parse {
    my ($self, $data_info) = @_;

	my $tm_flg = 0;
	my $tm_str;
	my $loadprof_flg = 0;
	my $loadprof_str;
	my $hit_flg = 0;
	my $hit_str;
	my $event_flg = 0;
    my $foreground_event_flg = 0;
	my $event_str;
	my $bgevent_flg = 0;
	my $bgevent_str;
    my $global_cache_flg = 0;
    my $global_cache_str;
    my $interconnect_ping_flg = 0;
    my @interconnect_ping_strs;

	my $step = 600;

    my %direct_path_event = ();

	$data_info->step($step);
	my $sec  = $data_info->start_time_sec->epoch;
	if (!$sec) {
		return;
	}
	open( IN, $data_info->input_file ) || die "@!";
	while (my $line = <IN>) {
		$line=~s/(\r|\n)*//g;			# trim return code
# print "$line\n";
		# 日付読込
		if ($line=~/^\s+End Snap:/) {
			$tm_flg = 1;
		} elsif ($line=~/^\s+Elapsed:/) {
			$tm_flg = 0;
		}
		if ($tm_flg == 1) {
			$tm_str .= ' '. $line;
		}

		# ロードプロファイル読込
		if ($line=~/^Load Profile/) {
			$loadprof_flg = 1;
		}
		if ($loadprof_flg == 1 && $line=~/^$/) {
			$loadprof_flg = 0;
		}
		if ($loadprof_flg == 1) {
# print "LOAD:$line\n";
			$loadprof_str .= ' '. $line;
		}

		# ヒット率読込
		if ($line=~/^Instance Efficiency Percentages/) {
			$hit_flg = 1;
		}
		if ($hit_flg == 1 && $line=~/^$/) {
			$hit_flg = 0;
		}
		if ($hit_flg == 1) {
# print "HIT:$line\n";
			$hit_str .= ' '. $line;
		}

        # フォアグラウンドイベント読込
        if ($line=~/Foreground Events by Total Wait Time/) {
            $event_flg = 1;
        } elsif ($line=~/Wait Classes by Total Wait Time/) {
            $event_flg = 0;
        }
        if ($event_flg == 1) {
            $event_str .= ' '. $line;
        }
        # バックグラウンドイベント読込
        if ($line=~/Background Wait Events/) {
            $bgevent_flg = 1;
        } elsif ($line=~/^\s+-------------/) {
            $bgevent_flg = 0;
        }
        if ($bgevent_flg == 1) {
 # print "BG:$line\n";
            $bgevent_str .= ' '. $line;
        }

        # グローバルキャッシュプロファイル読込
        if ($line=~/Global Cache Load Profile/) {
            $global_cache_flg = 1;
        } elsif ($line=~/^\s*Global Cache Efficiency/) {
            $global_cache_flg = 0;
        }
        if ($global_cache_flg == 1) {
 # print "BG:$line\n";
            $global_cache_str .= ' '. $line;
        }

        # インターコネクトPINGレイテンシー読込
        if ($line=~/Interconnect Ping Latency Stats/) {
            $interconnect_ping_flg = 1;
        } elsif ($line=~/^\s*Interconnect Throughput by ClientDB/) {
            $interconnect_ping_flg = 0;
        }
        if ($interconnect_ping_flg == 1) {
 # print "BG:$line\n";
            push (@interconnect_ping_strs, $line);
        }

        if ($foreground_event_flg && $line=~/^direct path (read|write) temp\s+(.+?)\s/) {
            my ($io, $waits) = ($1, $2);
            $waits=~s/,//g;
            $direct_path_event{$sec}{$io} = $waits;
        }
	}
	close(IN);

    # print Dumper \@interconnect_ping_strs;
	if ($tm_str=~/(\d\d)-\s*(.*?)\s*-(\d\d) (\d\d):(\d\d):(\d\d)/) {
		my ($DD, $MM, $YY, $hh, $mm, $ss) = ($1, $2, $3, $4, $5, $6);
		if (defined($months->{$MM})) {
			$MM  = $months->{$MM} - 1;
			$sec = timelocal($ss, $mm, $hh, $DD, $MM, $YY-1900+2000);
		}
	}

	# 各ブロックのレポートをデータに変換
	my %loadprof = parse_loadprof($loadprof_str);
	my %hit = parse_hit($hit_str);
    my %event = parse_event($event_str, $bgevent_str);
    my %global_cache = parse_global_cache($global_cache_str);
    my %interconnect_ping = parse_interconnect_ping(\@interconnect_ping_strs);

	# # ロードプロファイルの出力
	$data_info->is_remote(1);
	my $host = $data_info->file_name;
	$host=~s/^.+_//g;
	{
		my @header = keys %{$headers->{load_profiles}};
		my $output  = "Oracle/${host}/ora_load.txt";
		my %data    = ($sec => \%loadprof);
		$data_info->regist_metric($host, 'Oracle', 'ora_load', \@header);
		$data_info->pivot_report($output, \%data, \@header);
	}
	{
		my @header = keys %{$headers->{hits}};
print Dumper \@header;
		my $output  = "Oracle/${host}/ora_hit.txt";
		my %data    = ($sec => \%hit);
		$data_info->regist_metric($host, 'Oracle', 'ora_hit', \@header);
		$data_info->pivot_report($output, \%data, \@header);
	}
	{
		my @header = keys %{$headers->{events}};
		my $output  = "Oracle/${host}/ora_event.txt";
		my %data    = ($sec => \%event);
		$data_info->regist_metric($host, 'Oracle', 'ora_event', \@header);
		$data_info->pivot_report($output, \%data, \@header);
	}
    {
        my @header = qw/read write/;
        my $output  = "Oracle/${host}/ora_direct_path_io_temp.txt";
        $data_info->regist_metric($host, 'Oracle', 'ora_direct_path_io_temp', \@header);
        $data_info->pivot_report($output, \%direct_path_event, \@header);
    }
    {
        my @header = qw/traffic/;
        # print Dumper \%global_cache;
        my $output  = "Oracle/${host}/ora_global_cache_traffic.txt";
        my %data    = ($sec => \%global_cache);
        $data_info->regist_metric($host, 'Oracle', 'ora_global_cache_traffic', \@header);
        $data_info->pivot_report($output, \%data, \@header);
    }
    {
        my @header = qw/latency/;
        for my $instance(keys %interconnect_ping) {
            my $output  = "Oracle/${host}/device/ora_interconnect_ping__${instance}.txt";
            my %data    = ($sec =>  $interconnect_ping{$instance});
            print "INS:$instance,$output\n";
            print Dumper \%data;
            $data_info->regist_device($host, 'Oracle', 'ora_interconnect_ping',
                                      $instance, $instance, \@header);
            $data_info->simple_report($output, \%data, \@header);
        }

        # my %data    = ($sec => \%global_cache);
        # $data_info->regist_metric($host, 'Oracle', 'ora_global_cache_traffic', \@header);
        # $data_info->pivot_report($output, \%data, \@header);
    }

        # if ($device_info) {
        #     my $output_file = "device/iostat__${device}.txt";
        #     $data_info->regist_device($host, 'Linux', 'iostat', $device, $device_info, \@headers);
        #     $data_info->pivot_report($output_file, $results{$device}, \@headers);
        # }

	return 1;
}

1;
