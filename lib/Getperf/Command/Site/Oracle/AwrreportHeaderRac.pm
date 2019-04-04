package Getperf::Command::Site::Oracle::AwrreportHeaderRac;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw/get_headers get_months/;
our @EXPORT_OK = qw/get_headers get_months/;

sub get_headers {
	{
    # Time Model
		time_models => {
			'DBtime'         => 'DB time',
			'DBCPU'          => 'DB CPU',
			'DBEla'          => 'SQL Ela',
			'SQLParse'       => 'SQL Parse Ela',
			'HardParseEla'   => 'Hard Parse Ela',
			'HardParsePLSQL' => 'Hard Parse PL/SQL Ela',
			'HardParseJava'  => 'Hard Parse Java Ela',
			'bgtime'         => 'bg time',
			'bgCPU'          => 'bg CPU',
		},

    _time_models => [
      'DBtime'         ,
      'DBCPU'          ,
      'DBEla'          ,
      'SQLParse'       ,
      'HardParseEla'   ,
      'HardParsePLSQL' ,
      'HardParseJava'  ,
      'bgtime'         ,
      'bgCPU'          ,
    ],

    # Foreground Wait Classes
    'foreground_waits' => {
      'UserIO'   => 'User I/O(s)',
      'SysIO'    => 'Sys I/O(s)',
      'Other'    => 'Other(s)',
      'Applic'   => 'Applic (s)',
      'Commit'   => 'Commit (s)',
      'Network'  => 'Network (s)',
      'Concurcy' => 'Concurcy (s)',
      'Config'   => 'Config (s)',
      'Cluster'  => 'Cluster (s)',
      'DBCPU'    => 'DB CPU (s)',
      'DBTime'   => 'DB time',
    },

    '_foreground_waits' => [
      'UserIO',
      'SysIO',
      'Other',
      'Applic',
      'Commit',
      'Network',
      'Concurcy',
      'Config',
      'Cluster',
      'DBCPU',
      'DBTime',
    ],

    # Top Timed Events
    events => {
      'GcCrBlockBusy'  => 'gc cr block busy',
      'GcCrBlock3way'  => 'gc cr block 3-way',
      'DirectRd'       => 'direct path read',
      'DBCpu'          => 'DB CPU',
      'LatchCache'     => 'latch: cache buffers chains',
      'GcBufferBusy'   => 'gc buffer busy acquire',
      'EnqPs'          => 'enq: PS - contention',
      'ReliableMsg'    => 'reliable message',
      'IPCSync'        => 'IPC send completion sync',
      'PXDeqSlaveSes'  => 'PX Deq: Slave Session Stats',
      'GcCrMultiBlock' => 'gc cr multi block request',
      'LatchFree'      => 'latch free',
    },
    _events => [
      'GcCrBlockBusy',
      'GcCrBlock3way',
      'DirectRd',
      'DBCpu',
      'LatchCache',
      'GcBufferBusy',
      'EnqPs',
      'ReliableMsg',
      'IPCSync',
      'PXDeqSlaveSes',
      'GcCrMultiBlock',
      'LatchFree',
    ],

    # Top Timed Background Events
    bg_events => {
      'CPUTime'          => 'background cpu time', 
      'GCGrant2way'      => 'gc current grant 2-way', 
      'LatchFree'        => 'latch free', 
      'GCMultBlkRd'      => 'gc current multi block request', 
      'ReliableMsg'      => 'reliable message', 
      'GCGrantCongested' => 'gc current grant congested', 
      'PXDeq'            => 'PX Deq: Slave Join Frag', 
      'EnqFB'            => 'enq: FB - contention', 
      'BuffBusyWait'     => 'buffer busy waits', 
      'EnqTx'            => 'enq: TX - contention', 
    },
    _bg_events => [
      'CPUTime',
      'GCGrant2way',
      'LatchFree',
      'GCMultBlkRd',
      'ReliableMsg',
      'GCGrantCongested',
      'PXDeq',
      'EnqFB',
      'BuffBusyWait',
      'EnqTx',
    ],

    # System Statistics - Per Second : SystemStatistics
    sys_statistics => {
      'LogicalReads'   => 'Logical Reads/s',
      'PhysicalReads'  => 'Physical Reads/s',
      'PhysicalWrites' => 'Physical Writes/s',
      'RedoSize'       => 'Redo Size (k)/s',
      'BlockChanges'   => 'BlockChanges/s',
      'Calls'          => 'Calls/s',
      'Execs'          => 'Execs/s',
      'Parses'         => 'Parses/s',
      'Logons'         => 'Logons/s',
      'Txns'           => 'Txns/s',
    },

    _sys_statistics => [
      'LogicalReads',
      'PhysicalReads',
      'PhysicalWrites',
      'RedoSize',
      'BlockChanges',
      'Calls',
      'Execs',
      'Parses',
      'Logons',
      'Txns',
    ],

    # Global Cache Efficiency Percentages : CacheEfficiency
    cache_efficiencys => {
        'Local'  => 'Local %',
        'Remote' => 'Remote %',
        'Disk'   => 'Disk %',
    },

    _cache_efficiencys => [
        'Local',
        'Remote',
        'Disk',
    ],

    # Ping Statistics : PingStatistics
    ping_statistics => {
      '500bytes' => '500 bytes',
      '8Kbytes'  => '8 Kbytes',
    },
    _ping_statistics => [
      '500bytes',
      '8Kbytes',
    ],

    # Interconnect Client Statistics (per Second) : InterconnectTraffic
    interconnect_traffics => {
      'Sent'     => 'Sent (MB/s)',
      'Received' => 'Received (MB/s)',
    },
    _interconnect_traffics => [
      'Sent',
      'Received',
    ],

	};
}

sub get_months {
	{
    '1月', 1, '2月', 2, '3月', 3, '4月', 4, '5月', 5, '6月', 6, '7月', 7,
    '8月', 8, '9月', 9, '10月', 10, '11月', 11, '12月', 12,
    'Jan', 1, 'Feb', 2, 'Mar', 3, 'Apr', 4, 'May', 5, 'Jun', 6, 'Jul', 7,
    'Aug', 8, 'Sep', 9, 'Oct', 10, 'Nov', 11, 'Dec', 12
    };

}

1;
