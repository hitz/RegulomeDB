use strict;
use warnings;
use Test::More 'no_plan';
use Test::Mojo;
use Data::Dumper;

use lib "./lib";
use_ok ('Regulome');

use_ok("Regulome::RegulomeDB");
my $sampleDataFile = 't/data/sampleBED.pm';
## note this file contains matches to RegDB version 1.0 10/5/11 and might fail if data is updated.
my $sampleBED = do $sampleDataFile || die "Could not open $sampleDataFile";
=pod
 a hash of 
"bed input" => { score => ..
		         results => ..
		         refs => ..
	}
}
=cut
my $sampleFullBED = {'chr10	65587	65588	some	random	stuff	rs1938812  whatiever=something		' 
	=> 'chr10    65587       65588'};

my $sampleVCF = {
	# note: fake data
'chr1	100001201	rs76402894	C	A	159.42	LOW	GT_MATCH=1.00;AL_MATCH=1.00;PLAT=IL;VAL=N/A;SM=IL_BLOOD	GT:A1:A2	0/1:C:A
'	=> 'chr1    100001200       100001201'
};

my $sampleGFF = {
	# note: fake data
'chr6	user	      SNP	138022520	138022520	.		+	0	PMID=1656391
'	=> 'chr6    138022519       138022520'
};

# generic is tested as Range in SnpDB.t

my (@pos) = ("chr11",6608467);

#my $rdb = RegulomeDB->new({ type=>'multi', dbdir=>'./data/RegulomeDB'});
my $r = Test::Mojo->new('Regulome')->app();
#$r->log->handle('STDERR');
#$r->log->debug("TEST");
my $rdb = $r->rdb;
isa_ok($rdb,'RegulomeDB');
my ($format, $chk) = $r->check_coord(\@pos);
is(ref($chk),'ARRAY',"check_coord returns ARRAY_REF");

for my $c (keys %$sampleBED) {
	($format, $chk) = $r->check_coord($c);
	is($format, 'BED - 0 Based');
	my $scan = $rdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$c}->{results},"Check BED results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$c}->{refs},"Check BED refs $chk->[0] $chk->[1]");
	is($rdb->score($scan), $sampleBED->{$c}->{score}, "Check BED score $chk->[0] $chk->[1]");
}

for my $vcf (keys %$sampleVCF) {
	($format, $chk) = $r->check_coord($vcf);
	is($format, 'VCF - 1 Based');
	my $scan = $rdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleVCF->{$vcf}}->{results},"Check VCF results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleVCF->{$vcf}}->{refs},"Check VCF refs $chk->[0] $chk->[1]");
	is($rdb->score($scan), $sampleBED->{$sampleVCF->{$vcf}}->{score}, "Check VCF score $chk->[0] $chk->[1]");
}

for my $gff (keys %$sampleGFF) {
	($format, $chk) = $r->check_coord($gff);
	is($format, 'GFF - 1 Based');
	my $scan = $rdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleGFF->{$gff}}->{results},"Check GFF results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleGFF->{$gff}}->{refs},"Check GFF refs $chk->[0] $chk->[1]");
	is($rdb->score($scan), $sampleBED->{$sampleGFF->{$gff}}->{score}, "Check GFF score $chk->[0] $chk->[1]");
}

for my $bed (keys %$sampleFullBED) {
	($format, $chk) = $r->check_coord($bed);
	is($format, 'BED - 0 Based');
	my $scan = $rdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleFullBED->{$bed}}->{results},"Check full BED results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleFullBED->{$bed}}->{refs},"Check full BED refs $chk->[0] $chk->[1]");
	is($rdb->score($scan), $sampleBED->{$sampleFullBED->{$bed}}->{score}, "Check full BED score $chk->[0] $chk->[1]");
}
