#!/usr/bin/perl

#This script takes as input a list of dbSNP rsids and converts them to BED
# format coordinates.
# eg. pipe input of the following:
# rs78624811
# rs2395560
# rs3846863
# rs74671496
# rs4532437
# rs114008279
# Output:
#chr6	34413123	34413124
#chr6	34413207	34413208
#chr6	34413536	34413537
#chr6	34413674	34413675
#chr6	34414026	34414027
#chr6	34414641	34414642

$usage = qq(
Usage: $0 <dbSNP database> < <list of rsIDs>
\n);
die($usage) if (@ARGV != 1);

use DBI;

$DATABASE = shift(@ARGV);

%sth = ();

my $dbfile = $DATABASE;
my $db = DBI->connect("dbi:SQLite:dbname=$dbfile","","",
	{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

$db->do("PRAGMA cache_size = 1000000");
$db->commit;

$sth = $db->prepare("SELECT chrom, position FROM data WHERE rsid = ?");

while($line = <>) {  # no error checking here yet
	next if($line =~ /^#/);
	chomp($line);

	my @output = ();
	$sth->execute($line);
	my $results = $sth->fetchall_arrayref();
	foreach $row (@$results) {
		my($chrom, $pos) = @$row;
		$end = $pos + 1;
		$res = $chrom . "\t" . $pos . "\t" . $end;
		push(@output, $res);
	}
	print join("\n", @output) . "\n";
}

$db->disconnect;

