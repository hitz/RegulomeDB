#!/usr/bin/perl

#This script takes as input a specific coordinate (chr1:14342342) to rsID.
# eg. pipe input of the following:
# chr6:34413123
# Output:
# rs78624811

$usage = qq(
Usage: $0 <dbSNP database> <coordinate>
\n);
die($usage) if (@ARGV != 2);

use DBI;

$DATABASE = shift(@ARGV);
$COORDINATE = shift(@ARGV);

my($chrom, $pos) = split(":",$COORDINATE);

my $dbfile = $DATABASE;
my $db = DBI->connect("dbi:SQLite:dbname=$dbfile","","",
	{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

$sth = $db->prepare("SELECT rsid FROM data WHERE chrom == ? AND position == ?");
$sth->execute($chrom, $pos);
my $results = $sth->fetchall_arrayref();
foreach $row (@$results) {
	my($res) = @$row;
	print $res . "\n";
}

$db->disconnect;

