#!/usr/bin/perl

#This script takes as input a region (chr1:100-10000) to a list of coordinates
# in BED format.
# eg. input of the following:
# chr6:34413000-34414000
# Output:
# chr6	34413003	34413004
# chr6	34413084	34413085
# chr6	34413123	34413124
# chr6	34413207	34413208
# chr6	34413367	34413368
# chr6	34413536	34413537
# chr6	34413674	34413675
# chr6	34413872	34413873
# chr6	34413953	34413954
# chr6	34413972	34413973

$usage = qq(
Usage: $0 <dbSNP database> <region>
\n);
die($usage) if (@ARGV != 2);

use DBI;

$DATABASE = shift(@ARGV);
$REGION = shift(@ARGV);

my($chrom, $start, $stop) = $REGION =~ /(chr.+):(\d+)-(\d+)/;

my $dbfile = $DATABASE;
my $db = DBI->connect("dbi:SQLite:dbname=$dbfile","","",
	{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

$sth = $db->prepare("SELECT chrom, position FROM data, data_" . $chrom . "_index  WHERE data.id=data_" . $chrom . "_index.id AND minX >= ? AND maxX <= ?");
$sth->execute($start, $stop);
my $results = $sth->fetchall_arrayref();
foreach $row (@$results) {
	my($snp_chr, $snp_pos) = @$row;
	my $snp_end = $snp_pos + 1;
	print $snp_chr . "\t" . $snp_pos . "\t" . $snp_end . "\n";
}

$db->disconnect;

