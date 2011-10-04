use strict;
use warnings;
use Test::More 'no_plan';
use Data::Dumper;

use lib "../lib";
use RegulomeDB;
my $sampleBED = {
"chr1    10488313        10488314" => 1.1,
"chr1    46649045        46649046" => 1.2,
"chr1    100001200       100001201" => 1.3,
"chr6    138043309       138043310" => 1.4,
"chr6    137891882       137891883" => 1.5,
"chr6    138022519       138022520" => 2,
"chr6    138047319       138047320" => 3
};

my $sampleVCF = {};

my $sampleGeneric = {};

my $sampleGFF = {};

my $scoreTest = {
	[] => 5,
	['PWM_ELF5'] => 4,
	['PWM_FOXI1','PWM_FOXP1','PWM_HFH1(FOXQ1)'] => 4,
};

my (@triple) = ("chr11",6608467,6618467);

my $rdb = RegulomeDB->new({ type=>'multi', dbdir=>'./RegulomeDB/RDB'});
isa_ok($rdb,'RegulomeDB');
for my $c (keys %$sampleBED) {
	my ($format, @check) = $rdb->check_coord($c);
	print Dumper $rdb->process(@check);
}



