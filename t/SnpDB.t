use strict;
use warnings;
use Test::More 'no_plan';
use Test::Mojo;
use Data::Dumper;

use lib "./lib";
use_ok ('Regulome');

use_ok("Regulome::SnpDB");
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

my $sampleRange = {
	# note: fake data
'chr1:100001100..100001500'	=> [
          [
            'chr1',
            100001200
          ],
          [
            'chr1',
            100001232
          ],
          [
            'chr1',
            100001265
          ],
          [
            'chr1',
            100001482
          ]
        ]
};

my $sampleGFFrange = {
	# note: fake data
'chr6	user	      feature	138022520	138023100	.		+	0	PMID=1656391'
	=> [ [
            'chr6',
            138022539
          ],
          [
            'chr6',
            138022622
          ],
          [
            'chr6',
            138022645
          ],
          [
            'chr6',
            138022803
          ],
          [
            'chr6',
            138022872
          ],
          [
            'chr6',
            138023047
          ],
          [
            'chr6',
            138023093
          ],
]
};

my $sampleBEDrange = {
'chr10	61004	70000	some	random	stuff	rs1938812' => [
          [
            'chr10',
            61019
          ],
          [
            'chr10',
            68239
          ],
          [
            'chr10',
            68490
          ],
          [
            'chr10',
            68574
          ],
          [
            'chr10',
            68812
          ]
]
};

my $allTest = {rs55998931 => ['chr1','10491']};
my $commonTest = { rs28675701 => ['chrX','60592']};


my $snpdb = SnpDB->new({ type=>'single', 
					     dbfile_all=>'./data/SnpDB/dbSNP132.db',
						 dbfile_common =>'./data/SnpDB/dbSNP132.db'});
isa_ok($snpdb,'SnpDB');

while (my ($snpid, $c) = each (%$allTest)) {
	is($snpdb->getRsid($c), $snpid,  "check getRsid");
	is_deeply($snpdb->getSNPbyRsid($snpid), $c, "check getSNPbyRsid")
}

my ($format, $chk) = ('',[]);
=pod
for my $c (keys %$sampleBEDrange) {
	($format, $chk) = $r->check_coord($c);
	is($format, 'BED - 0 Based');
	my $scan = $snpdb->process(@$chk);
	is_deeply([ map $_->[0], @$scan ], $sampleBED->{$c}->{results},"Check BED results $chk->[0] $chk->[1]");
	is_deeply([ map $_->[1], @$scan ], $sampleBED->{$c}->{refs},"Check BED refs $chk->[0] $chk->[1]");
	is($snpdb->score($scan), $sampleBED->{$c}->{score}, "Check BED score $chk->[0] $chk->[1]");
}
=cut

my $r = Test::Mojo->new('Regulome')->app();

# check_coord with a range checks SnpDB::getSNPbyRange()
for my $rng (keys %$sampleRange) {
	($format, $chk) = $r->check_coord($rng);
	is($format, 'Generic - 1 Based', "check format (generic range)");
	is_deeply($chk, $sampleRange->{$rng}, "Check Generic range -> SNP");
}

for my $gff (keys %$sampleGFFrange) {
	($format, $chk) = $r->check_coord($gff);
	is($format, 'GFF - 1 Based', "check format (gff range)");
	is_deeply($chk, $sampleGFFrange->{$gff}, "Check GFF range -> SNP");	
}

for my $bed (keys %$sampleBEDrange) {
	($format, $chk) = $r->check_coord($bed);
	is($format, 'BED - 0 Based', "check format (BED range)");
	is_deeply($chk, $sampleBEDrange->{$bed}, "Check BED range -> SNP");	
}
