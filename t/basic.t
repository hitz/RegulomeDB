#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 13;
use Test::Mojo;
use Mojo::Log;
use Benchmark qw(:all :hireswallclock);
use lib './lib';
use_ok 'Regulome';

my $testSubmit = "
	rs13343114
11 5248490	5248491
4:33493..36333
chr6    138043309 138043310
7 88888 99999
 x:55041617-55041641
 chr1	41981	rs806721	A	G	98	LOW	GT_MATCH=1.00;AL_MATCH=1.00;PLAT=CG;VAL=N/A;SM=CG_BLOOD,CG_SALIVA	GT:A1:A2	1/1:G:G
 chrX	user	      TF_binding_site	48644374	48644376	.		+	0	PMID=1656391
 chrY	59033300	rs62604356	C	T	1927.89	HIGH	GT_MATCH=0.50;AL_MATCH=0.50;PLAT=CG,IL;VAL=N/A;SM=IL_BLOOD,IL_SALIVA,CG_BLOOD,CG_SALIVAGT:A1:A2	1/1:T:T
";
$ENV{MOJO_CHUNK_SIZE} = 2621440;
$ENV{MOJO_MAX_MESSAGE_SIZE} = 10000000000; # 10 GB upload limit
$ENV{MOJO_MAX_MEMORY_SIZE}  = 10000000000; # 10 GB upload limit

my $testFile = "t/data/Regulome-DB-20.vcf";
ok("-e $testFile", "does file exist");
my $testBig = "t/data/Regulome-DB-10K.vcf";
ok("-e $testBig", "does big file exist");
my $testBig2 = "t/data/Regulome-DB-last10K.vcf";
ok("-e $testBig2", "does 2nd big file exist");

my $t = Test::Mojo->new('Regulome');
$t->app->log( Mojo::Log->new() );
$t->app->log->level('debug');
$t->app->log->path('./test.log');
$t->app->log->debug("Starting test run for basic.t");

$t->get_ok('/welcome')->status_is(200)->content_like(qr/Mojolicious/i);
my $search = $t->get_ok('/search')->status_is(200);

my $run_data = $t->post_form_ok('/running' => {data => $testSubmit});
$run_data->status_is(200)->content_like(qr/Elapsed/);


for my $f ($testFile, $testFile, $testBig2, $testBig, $testBig, $testFile, $testBig2, $testFile, $testBig) {

    print STDERR "Testing $f\n...";
    my $run_file = $t->post_form_ok('/running' => {file_data => { file => $f} });
    $run_file->status_is(200)->content_like(qr/Elapsed/);

}

for my $f ($testFile, $testFile, $testBig2, $testBig, $testBig, $testFile, $testBig2, $testFile, $testBig) {

    print STDERR "Testing $f\n...";
    my $run_file = $t->post_form_ok('/fastrun' => {file_data => { file => $f} });
    $run_file->status_is(200)->content_like(qr/Elapsed/);

}

# TODO unit tests for /snp/:id and /snp/:chr/:pos and static about, help, index pages.
