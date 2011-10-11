use strict;
use warnings;
use Test::More 'no_plan';
use Test::Mojo;
use Data::Dumper;

use lib "./lib";
use_ok ('Regulome');

use_ok("Regulome::SnpDB");

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
my $commonTest = { 
	rs11703994 => [ 'chr22', 16053790],
#	rs28675701 => ['chrX','60592'] some issue with sex chromosomes?
};

my $snpResult = { rs55998931 => [
          [
            'DNase_Be2c',
            'NCP000',
            '10420',
            '10570'
          ],
          [
            'DNase_Hvmf',
            'NCP000',
            '10440',
            '10590'
          ],
          [
            'DNase_Jurkat',
            'NCP000',
            '10440',
            '10590'
          ],
          [
            'DNase_Nb4',
            'NCP000',
            '10440',
            '10590'
          ],
          [
            'TF_H1-hESC_TAF7',
            'NCP000',
            '10332',
            '10536'
          ],
          [
            'TF_HepG2_ZBTB33',
            'NCP000',
            '10382',
            '10578'
          ]
   ]
};

my $snpdb = SnpDB->new({ type=>'single', 
					     dbfile_all=>'./data/SnpDB/dbSNP132.db',
						 dbfile_common =>'./data/SnpDB/dbSNP132Common.db'});
isa_ok($snpdb,'SnpDB');

while (my ($snpid, $c) = each (%$commonTest)) {
	is($snpdb->getRsid($c), $snpid,  "check comon getRsid");
	is_deeply($snpdb->getSNPbyRsid($snpid), $c, "check common getSNPbyRsid");
	my $sth = $snpdb->dbs->{common}->prepare("select chrom, position from data where rsid = ?");
	$sth->execute($snpid);
	my $res = $sth->fetchall_arrayref;
	is_deeply($res, [ $c ], "Sanity check of commonSNP db");
}

my ($format, $chk) = ('',[]);

my $r = Test::Mojo->new('Regulome')->app();
while (my ($snpid, $c) = each (%$allTest)) {
	is($snpdb->getRsid($c), $snpid,  "check all getRsid");
	my $snp = $snpdb->getSNPbyRsid($snpid);
	is_deeply($snp, $c, "check all getSNPbyRsid");
	($format, $chk) = $r->check_coord($snpid);
	is(scalar(@$chk),1,"Only 1 coord returned for SNP");
	my $scan = $r->rdb->process($chk->[0]);
	is_deeply($scan, $snpResult->{$snpid},"check SNP result");
}



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
