#!/usr/bin/env perl
use strict;
use warnings;
use Test::More 'no_plan';
use Test::Mojo;
use Data::Dumper;

use lib "./lib";
use_ok ('Regulome');

use_ok("Regulome::RegulomeDB");
use_ok("Regulome::RDB");
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

my (@pos1) = ("chrx",6608467);
my (@pos2) = ("y", 138022519);
#my $rdb = RegulomeDB->new({ type=>'multi', dbdir=>'./data/RegulomeDB'});
my $r = Test::Mojo->new('Regulome')->app();
#$r->log->handle('STDERR');
#$r->log->debug("TEST");
my $rdb = $r->rdb;
isa_ok($rdb,'Regulome::RegulomeDB');
my $cntrl = Regulome::RDB->new();
isa_ok($cntrl, 'Regulome::RDB');
my ($format, $chk) = $cntrl->check_coord(\@pos1);
is(ref($chk),'ARRAY',"check_coord returns ARRAY_REF");
is(ref($chk->[0]),'ARRAY',"check_coord returns ARRAY_REF of ARRAY_REF");
($format, $chk) = $cntrl->check_coord(\@pos2);


#open (OUT,">tmp.pm"); #see note below
#my $out = {};
for my $c (keys %$sampleBED) {
	($format, $chk) = $cntrl->check_coord($c);
	is(scalar(@$chk), 1, "BED returns 1 SNP");
	my $snp = $chk->[0];
	is($format, 'BED - 0 Based',"Check BED format");
	my $scan = $rdb->process($snp);
	#print Dumper $scan;
	# note: coordinates of process thrown out, checked in SnpDB.t
	#is_deeply([ map $_->[0], @$scan ], $sampleBED->{$c}->{results},"Check BED results $snp->[0] $snp->[1]");
	#is_deeply([ map $_->[1], @$scan ], $sampleBED->{$c}->{refs},"Check BED refs $snp->[0] $snp->[1]");
	my $sc;
	is_deeply(($sc = $rdb->score($scan,$snp->[0])), $sampleBED->{$c}->{score}, "Check BED score $snp->[0] $snp->[1]");
#   Below code is useful for regenerating sampleBED.pm when database or scoring changes.
=pod
	$out->{$c} = { 
		score => $sc
	};
=cut
}
# see above note
#print OUT Dumper $out;
#exit;
for my $vcf (keys %$sampleVCF) {
	($format, $chk) = $cntrl->check_coord($vcf);
	is($format, 'VCF - 1 Based', "Check VCF format");
	is(scalar(@$chk), 1, "VCF returns 1 SNP");
	my $snp = $chk->[0];
	my $scan = $rdb->process($snp);
	#is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleVCF->{$vcf}}->{results},"Check VCF results $snp->[0] $snp->[1]");
	#is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleVCF->{$vcf}}->{refs},"Check VCF refs $snp->[0] $snp->[1]");
	is_deeply($rdb->score($scan,$snp->[0]), $sampleBED->{$sampleVCF->{$vcf}}->{score}, "Check VCF score $snp->[0] $snp->[1]");
	#is($rdb->full_score($scan,$snp->[0])->{score}, $sampleBED->{$sampleVCF->{$vcf}}->{score}, "Check VCF score_full $snp->[0] $snp->[1]");
}


for my $gff (keys %$sampleGFF) {
	($format, $chk) = $cntrl->check_coord($gff);
	is($format, 'GFF - 1 Based',"check GFF format");
	is(scalar(@$chk), 1, "GFF returns 1 SNP");
	my $snp = $chk->[0];
	my $scan = $rdb->process($snp);
	#is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleGFF->{$gff}}->{results},"Check GFF results $snp->[0] $snp->[1]");
	#is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleGFF->{$gff}}->{refs},"Check GFF refs $snp->[0] $snp->[1]");
	is_deeply($rdb->score($scan,$snp->[0]), $sampleBED->{$sampleGFF->{$gff}}->{score}, "Check GFF score $snp->[0] $snp->[1]");
	#is($rdb->full_score($scan,$snp->[0])->{score}, $sampleBED->{$sampleGFF->{$gff}}->{score}, "Check GFF score_full $snp->[0] $snp->[1]");
}

for my $bed (keys %$sampleFullBED) {
	($format, $chk) = $cntrl->check_coord($bed);
	is($format, 'BED - 0 Based', "check full BED format");
	is(scalar(@$chk), 1, "BED returns 1 SNP");
	my $snp = $chk->[0];
	my $scan = $rdb->process($snp);
	#is_deeply([ map $_->[0], @$scan ], $sampleBED->{$sampleFullBED->{$bed}}->{results},"Check full BED results $snp->[0] $snp->[1]");
	#is_deeply([ map $_->[1], @$scan ], $sampleBED->{$sampleFullBED->{$bed}}->{refs},"Check full BED refs $snp->[0] $snp->[1]");
	is_deeply($rdb->score($scan,$snp->[0]), $sampleBED->{$sampleFullBED->{$bed}}->{score}, "Check full BED score $snp->[0] $snp->[1]");
	#is($rdb->full_score($scan,$snp->[0])->{score}, $sampleBED->{$sampleFullBED->{$bed}}->{score}, "Check full BED score_full $snp->[0] $snp->[1]");
}

#TODO - add tests for all error states!
#TODO - split out tests for controller (check_coord)
#TODO - need tests for results of full_score as well as all datatypes (FP, MANUAL, VAL, etc.)
# most: rs505141
