#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More 'no_plan';
use Test::Mojo;
use Benchmark qw(:all :hireswallclock);
use lib './lib';
use_ok 'Regulome';
use_ok 'Regulome::RegulomeDB';

my $testSubmit = "
chrX	55034742	55034747	Hif1-alpha_regulatory_promoter_element;PMID21207956								
chrX	55034862	55034867	Hif1-alpha_regulatory_promoter_element;PMID21207956								
chrX	55034872	55034877	Hif1-alpha_regulatory_promoter_element;PMID21207956								
chrX	55035282	55035283	SNV;PMID7912287				
chrX	55041612	55041852	intronic_regulatory_region;PMID9642238	
chrX	55041616	55041640	GATA1_TF_binding_site;PMID9642238	
chrX	55041625	55041631	GATA1_regulatory_promoter_element;PMID9642238								
chrX	55041652	55041676	GATA1_TF_binding_site;PMID9642238	
chrX	55041669	55041690	SP1_TF_binding_site;PMID9642238		
chrX	55041676	55041684	CACCC_box;PMID9642238			
chrX	55041731	55041745	SP1_TF_binding_site;PMID9642238		
chrX	55041735	55041742	CACCC_box;PMID9642238			
chrX	55042332	55042497	genetic_marker;PMID1301172		
chrX	55057372	55057401	iron_responsive_element;PMID8509404	
chrX	55057381	55057573	SP1_TF_binding_site;PMID18555711	
chrX	55057381	55057707	p300_histone_deactylase_binding_site;PMID16904069								
chrX	55057384	55057390	iron_responsive_element;PMID8509404	
chrX	55057392	55057393	iron_responsive_element;PMID18823803	
chrX	55057401	55057450	promoter;PMID21309041			
chrX	55057426	55057450	non_canonical_TATA_box;PMID9334239	
chrX	55057433	55057441	non_canonical_TATA_box;PMID9334239	
chrX	55057438	55057704	promoter;PMID9334239			
chrX	55057458	55057470	CACCC_box;PMID9334239			
chrX	55057464	55057466	SP1_regulatory_promoter_element;PMID18555711								
chrX	55057498	55057522	GATA1_TF_binding_site;PMID9334239	
chrX	55057506	55057513	GATA1_regulatory_promoter_element;PMID9334239								
chrX	55057522	55057546	GATA1_TF_binding_site;PMID9334239	
chrX	55057531	55057537	GATA1_regulatory_promoter_element;PMID9334239								
chrX	55057540	55057585	SP1_TF_binding_site;PMID16904069	
chrX	55057551	55057553	SP1_TF_binding_site;PMID16904069|SP1_TF_binding_site;PMID18555711							
chrX	55057566	55057568	SP1_TF_binding_site;PMID16904069	
chrX	55057568	55057570	SP1_regulatory_promoter_element;PMID18555711								
chr11	5226168	5226240	CTCF_insulator_binding_site|TF_binding_site;PMID11997516
chr11	5246779	5246793	three_prime_UTR|ntr:PRE;PMID11486027			
chr11	5246821	5246822	SNV;PMID9792288						
chr11	5246957	5246958	canonical_three_prime_splice_site;PMID2987809		
chr11	5246958	5246959	three_prime_cis_splice_site;PMID2920213			
chr11	5246963	5246964	SNV;PMID7567451						
chr11	5247152	5247153	SNV;PMID18774771					
chr11	5247802	5247804	five_prime_cis_splice_site;PMID9427726			
chr11	5247805	5247806	canonical_five_prime_splice_site;PMID7151176		
chr11	5248031	5248032	three_prime_cis_splice_site;PMID2920213			
chr11	5248043	5248044	SNV;PMID3780671						
chr11	5248049	5248050	SNV;PMID3780671|SNV;PMID6264477|SNV;PMID6895866		
chr11	5248052	5248053	cryptic_splice_site_variant;PMID3879973			
chr11	5248065	5248066	branch_site;PMID3879973					
chr11	5248153	5248154	SNV;PMID17665502					
chr11	5248154	5248155	SNV;PMID12210807					
chr11	5248158	5248159	SNV;PMID11939510					
chr11	5248279	5248280	SNV;PMID11722417					
chr11	5248328	5248329	SNV;PMID2018842						
chr11	5248328	5248330	TATA_box;PMID16732578					
chr11	5248329	5248330	SNV;PMID2018842						
chr11	5248330	5248331	TATA_box;PMID3382401					
chr11	5248331	5248332	SNV;PMID2018842						
chr11	5248356	5248357	SNV;PMID18081706					
chr11	5248364	5248386	CP-1_TF_binding_site;PMID11069894|NF-y_TF_binding_site;PMID11069894|SP1_TF_binding_site;PMID11069894					
chr11	5248374	5248402	CP-1_TF_binding_site;PMID11069894			
chr11	5248387	5248388	SNV;PMID2018842						
chr11	5248388	5248389	SNV;PMID6086605						
chr11	5248401	5248402	CACCC_box;PMID10606872|CACCC_box;PMID15352994		
chr11	5248442	5248443	major_TSS;PMID6701091					
chr11	5248450	5248451	major_TSS;PMID6701091					
chr11	5248468	5248469	major_TSS;PMID6701091					
chr11	5248476	5248477	TSS;PMID6303333						
chr11	5248490	5248491	SNV;PMID18081706					
chr11	5248557	5248575	BP2_TF_binding_site;PMID10908341			
chr11	5248593	5248603	DLX4_TF_binding_site;PMID10908341			
chr11	5248606	5248628	HMG1/HMG2_TF_binding_site;PMID10908341			
chr11	5248821	5248847	DLX4_TF_binding_site;PMID17133428			
chr11	5248827	5248851	DLX4_TF_binding_site;PMID10908341			
chr11	5253995	5253996	GATA-1_TF_binding_site;PMID1309671			
chr11	5255569	5255570	canonical_five_prime_splice_site;PMID3401592		
chr11	5255792	5255793	SNV;PMID17916081					
chr11	5271064	5271087	STAT3_TF_binding_site;PMID11856732			
chr11	5271074	5271077	STAT3_TF_binding_site;PMID11856732			
chr11	5271111	5271117	TATA_box;PMID10196210					
chr11	5271120	5271158	methylated_base_feature;PMID7684493|SP1_TF_binding_site;PMID7684493|SSP_complex_TF_binding_site;PMID7684493				
chr11	5271128	5271136	regulatory_promoter_element;PMID10196210		
chr11	5271136	5271137	methylated_C;PMID7684493				
chr11	5271139	5271140	methylated_C;PMID7684493				
chr11	5271203	5271204	regulatory_promoter_element;PMID2578619;PMID2578620	
chr11	5271226	5271232	CACCC_box;PMID10196210					
chr11	5271261	5271262	SNV;PMID11285460					
chr11	5271276	5271306	promoter;PMID7684493|SP1_TF_binding_site;PMID7684493|SSP_complex_TF_binding_site;PMID7684493						
chr11	5271281	5271282	SNV;PMID11285460					
chr11	5271282	5271283	SNV;PMID6210198						
chr11	5271288	5271289	promoter;PMID7684493|SSP_complex_TF_binding_site;PMID7684493								
chr11	5271559	5271724	GATA-1_TF_binding_site;PMID18347053|Mi-2_chromatin_remodeling_factor_binding_site;PMID18347053|ZFPM1_TF_binding_site;PMID18347053	
chr11	5271647	5271651	GATA-1_TF_binding_site;PMID18347053			
chr11	5271649	5271650	GATA-1_TF_binding_site;PMID18347053			
chr11	5271668	5271630	GATA-1_TF_binding_site;PMID18347053			
chr11	5271811	5271461	silencer;PMID18347053					
chr11	5274635	5274655	canonical_three_prime_splice_site;PMID3857622		
chr11	5275515	5275521	canonical_five_prime_splice_site;PMID3857622		
chr11	5276049	5276780	regulatory_promoter_element;PMID19153051		
chr11	5276054	5276074	BCL11A_TF_binding_site;PMID19153051			
chr11	5276059	5276061	major_TSS;PMID6701091					
chr11	5276061	5276065	BCL11A_TF_binding_site;PMID19153051			
chr11	5276070	5270671	major_TSS;PMID6701091					
chr11	5276080	5276081	major_TSS;PMID6701091					
chr11	5276090	5270691	major_TSS;PMID6701091					
chr11	5276168	5276169	SNV;PMID16956833					
chr11	5276182	5276186	YY1_TF_binding_site;PMID2050690				
chr11	5276185	5276186	SNV;PMID2050690|SNV;PMID2462941				
chr11	5276185	5276199	YY1_TF_binding_site;PMID2050690				
chr11	5276186	5276181	octamer_binding_protein_octamer_motif;PMID2050690	
chr11	5276187	5276192	octamer_binding_protein_octamer_motif;PMID2050690	
chr11	5276196	5276199	YY1_TF_binding_site;PMID2050690				
chr11	5276319	5276320	SNV;PMID12082507					
chr11	5276496	5276644	GATA-1_TF_binding_site;PMID18347053|Mi-2_chromatin_remodeling_factor_binding_site;PMID18347053|ZFPM1_TF_binding_site;PMID18347053	
chr11	5276543	5276685	GATA-1_TF_binding_site;PMID18443038			
chr11	5276566	5276591	GATA-1_TF_binding_site;PMID18443038			
chr11	5276576	5276577	GATA-1_TF_binding_site;PMID18443038			
chr11	5276577	5276578	GATA-1_TF_binding_site;PMID18443038			
chr11	5277235	5277236	SNV;PMID10234511					
chr11	5277406	5277407	SNV;PMID10234511					
chr11	5291172	5291173	TSS;PMID6292831						
chr11	5291174	5291175	TSS;PMID6292831						
chr11	5291245	5291267	CP-1_TF_binding_site;PMID11069894|NF-y_TF_binding_site;PMID11069894|SP1_TF_binding_site;PMID11069894					
chr11	5291259	5291284	CP-1_TF_binding_site;PMID11069894|NF-y_TF_binding_site;PMID11069894|SP1_TF_binding_site;PMID11069894					
chr11	5291268	5291269	major_TSS;PMID6701091					
chr11	5291371	5291372	major_TSS;PMID6701091					
chr11	5291389	5291390	TSS;PMID6292831						
chr11	5301965	5301996	enhancer;PMID2116990					
chr11	5301970	5302015	enhancer;PMID2116990					
chr11	5301978	5302000	enhancer;PMID2116990					
chr11	5301979	5301982	AP1_complex_TF_binding_site;PMID2116990			
chr11	5301982	5301985	AP1_complex_TF_binding_site;PMID2116990			
chr11	5301985	5301988	AP1_complex_TF_binding_sitePMID2116990			
chr11	5301988	5301991	AP1_complex_TF_binding_site;PMID2116990			
chr11	5301991	5301994	AP1_complex_TF_binding_site;PMID2116990			
chr11	5301994	5301997	AP1_complex_TF_binding_site;PMID2116990			
chr11	5301997	5302000	AP1_complex_TF_binding_site;PMID2116990			
chr11	5312633	5312705	CTCF_insulator_binding_site;PMID11997516|CTCF_insulator_binding_site;PMID16230345|ZBTB33_insulator_binding_site;PMID16230345		
chrX	48641391	48641469	GATA-1_TF_binding_site;PMID1526579|LDB1_TF_binding_site;PMID15265794|LMO2_TF_binding_site;PMID15265794|TAL1_TF_binding_site;PMID15265794|TCF3_TF_binding_site;PMID15265794				
chrX	48641625	48641824	TP73_TF_binding_site;PMID19509292	
chrX	48644363	48644397	GATA-1_TF_binding_site;PMID1656391	
chrX	48644372	48644373	GATA-1_TF_binding_site;PMID1656391	
chrX	48644373	48644376	GATA-1_TF_binding_site;PMID1656391	
chrX	48644373	48644387	GATA-1_TF_binding_site;PMID1656391	
chrX	48644374	48644375	GATA-1_TF_binding_site;PMID1656391	
chrX	48644381	48644382	GATA-1_TF_binding_site;PMID1656391	
chrX	48644385	48644387	GATA-1_TF_binding_site;PMID1656391	
chrX	48644386	48644382	GATA-1_TF_binding_site;PMID1656391	
chrX	48644548	48644624	GATA-1_TF_binding_site;PMID15265794|LDB1_TF_binding_site;PMID15265794|TAL1_TF_binding_site;PMID15265794|TCF3_TF_binding_site;PMID15265794								
chrX	48644722	48644832	regulatory_promoter_element;PMID18195733|regulatory_promoter_element;PMID18195733					
chrX	48644832	48644876	SP1_TF_binding_site;PMID18195733	
chrX	48644832	48645053	promoter;PMID18195733			
chrX	48644857	48645028	SP1/SP3_TF_binding_site;PMID18195733	
chrX	48644873	48644893	CACCC_box;PMID18195733|SP1_CACCC_box;PMID18195733|SP1_CACCC_box;PMID18195733						
chrX	48644880	48644885	CACCC_box;PMID18195733			
chrX	48649496	48649497	canonical_five_prime_splice_site;PMID19260099								
chrX	48649735	48649745	five_prime_cis_splice_site;PMID12649131
chrX	48649736	48649737	canonical_five_prime_splice_site;PMID19633202								
chrX	48649737	48649738	canonical_five_prime_splice_site;PMID12649131								
chrX	48659125	48659203	GATA-1_TF_binding_site;PMID15265794|LDB1_TF_binding_site;PMID15265794|LMO2_TF_binding_site;PMID15265794|TAL1_TF_binding_site;PMID15265794|TCF3_TF_binding_site;PMID15265794";

my $testBedFile = 't/data/RegulomeDB-test.bed'; # exact content as above.

my $testFile = "t/data/Regulome-DB-20.vcf";
my $testFile2 = "t/data/Regulome-DB-160.vcf";
my $testBig = "t/data/Regulome-DB-10K.vcf";
my $testBig2 = "t/data/Regulome-DB-last10K.vcf";
my $testBigger = "t/data/Regulome-DB-100K.vcf";
my $testGenome = "t/data/snp-TEST20110209-final.vcf";


my $t = Test::Mojo->new('Regulome');

my $run_file;
=pod
$run_file = $t->post_form_ok('/running' => {file_data => { file => $testFile} });
$run_file->status_is(200)->content_like(qr/Elapsed/);
print STDERR "one\n";

$run_file = $t->post_form_ok('/running' => {file_data => { file => $testBig} });
$run_file->status_is(200)->content_like(qr/Elapsed/);
print STDERR "two\n";
=cut

$ENV{MOJO_CHUNK_SIZE} = 2621440;
$ENV{MOJO_MAX_MESSAGE_SIZE} = 5000000000; # 5 GB upload limit
$run_file = $t->post_form_ok('/running' => {file_data => { file => $testBigger} });
$run_file->status_is(200)->content_like(qr/Elapsed/);
print STDERR "three\n";

=pod

my $count = 5000; # do $count snps for each file
my $r = Test::Mojo->new('Regulome')->app();
use_ok('Regulome::RDB');
my $ctl = Regulome::RDB->new(app => $r);

my ($t0,$t0_5,$t1, $td);
for my $chr (1..22,'X','Y') {
	open(FH, "t/data/chr$chr.test.vcf") || die "could not open t/data/chr$chr.test.vcf";
	my $n = 0;
	$t0 = Benchmark->new;
	my @file = <FH>; # slurp
	my $nres = 0;
	my $t0_5 = Benchmark->new();
	print "Slurp time for ", scalar @file, " lines: ",timestr(timediff($t0_5,$t0)),"\n";
	for my $line (@file) {
		last if $n >= $count;
		next if($chr ne 'Y' && rand() <= 0.1); # skip 9/10 lines except for Y which is short
		$n++;
		#print "(line $n): $line";
		my ( $format, $snps ) = $ctl->check_coord($line);
		for my $snp (@$snps) {
			my $res      = $ctl->rdb->process($snp);
			$nres += scalar @$res;
			my $score          = $ctl->rdb->score($res);
		}		
	}
	$t1 = Benchmark->new;
	$td = timediff($t1, $t0);	
	print "$count random SNPS ($nres results) from chr$chr.vcf took: ",timestr($td),"\n";
	close(FH);
}
=pod

$t0 = Benchmark->new;
for my $line (split("\n"), $testLocal) {
		next
		  if ( !$line || $line =~ /^#/ || $line !~ /\d+/ );   # got to have some numbers!
	$regDB->check_coord($line);
}
$t1 = Benchmark->new;
$td = timediff($t1, $t0);
print "10K line check_coord",timestr($td),"\n";

cmpthese('2', {
	"BedRaw (157)" => sub { run_text($t, $testSubmit) },
	"BedFile (157)" => sub { run_file($t, $testBedFile) },
	"VcfFile (160)" => sub { run_file($t, $testFile2)},
	"VcfFile (10K)" => sub { run_file($t, $testBig)},
	"VcfLocalFile (10K)" => sub {run_text($t, $testLocal)},
	"VcfFile-rev (10K)" => sub { run_file($t, $testBig2)},
	"VcfLocalFile-rev (10K)" => sub {run_text($t, $testLocal2)},
});

sub run_file {
	my $app = shift;
	my $file = shift;
	my $out = $app->post_form_ok('/running' => {file_data => { file => $file} });
	$out->status_is(200)->content_like(qr/Elapsed/);
}

sub run_text {
	my $app = shift;
	my $data = shift;
	my $out = $app->post_form_ok('/running' => {data => $data});
	$out->status_is(200)->content_like(qr/Elapsed/);
}

my $time=timeit(10000,sub { $regDB->process($sample) });
print "10000 process (1a) queries took: ",timestr($time), "\n";
$time=timeit(10000,sub { $regDB->process($sampleB) });
print "10000 process (1b) queries took: ",timestr($time), "\n";
$time=timeit(10000,sub { $regDB->process($sampleX) });
print "10000 process (X) queries took: ",timestr($time), "\n";
my $res = $regDB->process($sampleX); 
cmpthese (1000, {
	score => sub { $regDB->score($res) },
	full_score => sub { $regDB->full_score($res, $sample->[0])},
	}
);


$time = timeit(10000,sub {$regDB->score($res)});
print "10000 scores took: ",timestr($time), "\n";
$time = timeit(10000, sub {});
print "10000 anon sub took: ",timestr($time),"\n";
$time = timeit(10000, sub { $regDB->nullop()} );
print "10000 method calls took: ",timestr($time),"\n";
$time = timeit(10000, sub { $regDB->nullop($res)} );
print "10000 method with arg took: ",timestr($time),"\n";


=cut
