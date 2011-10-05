use strict;
use warnings;
use Test::More 'no_plan';
use Test::Mojo;
use Data::Dumper;

use lib "./lib";
use_ok ('Regulome');

use_ok("Regulome::RegulomeDB");
my $sampleDataFile = 't/data/sampleBED.pm';
my $sampleBED = do $sampleDataFile || die "Could not open $sampleDataFile";
=pod
 a hash of 
"bed input" => { score => ..
		         results => ..
		         refs => ..
	}
}
=cut

my $sampleVCF = {};

my $sampleGeneric = {};

my $sampleGFF = {};

my $scoreTest = {
};

my (@pos) = ("chr11",6608467);

#my $rdb = RegulomeDB->new({ type=>'multi', dbdir=>'./data/RegulomeDB'});
my $r = Test::Mojo->new('Regulome')->app();
#$r->log->handle('STDERR');
#$r->log->debug("TEST");
my $rdb = $r->rdb;
isa_ok($rdb,'RegulomeDB');
my ($format, $chk) = $r->check_coord();
is(ref($chk),'ARRAY',"check_coord returns ARRAY_REF");

for my $c (keys %$sampleBED) {
	($format, $chk) = $r->check_coord($c);
	my $scan = $rdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$c}->{results},"Check BED results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$c}->{refs},"Check BED refs $chk->[0] $chk->[1]");
	is($rdb->score($scan), $sampleBED->{$c}->{score}, "Check Score $chk->[0] $chk->[1]");
}


