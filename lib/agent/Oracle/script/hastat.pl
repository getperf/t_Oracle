#!//usr/bin/perl
#        inet 10.152.16.67 netmask fffff800 broadcast 10.152.23.255

my @buf = `/sbin/ifconfig -a`;
my %services = (
	'192.168.10.2' => 'orcl',
);

for my $line(@buf) {
	if ($line=~/(inet.*?)(\d.*?)\s/) {
		my $ip = $2;
		if (defined(my $service = $services{$ip})) {
			print $service . "\n";
		}
	}
}
