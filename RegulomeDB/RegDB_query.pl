#!/usr/bin/perl

$usage = qq(
Usage: $0 <single|multi> <Query file> <Database Directory>
\n);
die($usage) if (@ARGV != 3);

use DBI;

my $TYPE = shift(@ARGV);
die if($TYPE != "single" && $TYPE != "multi"); #testing file structure
my $QUERY_FILE = shift(@ARGV);
my $DB_DIR = shift(@ARGV);

%sth = ();
%dbs = ();

if($TYPE eq "single") {
	my $dbfile = $DB_DIR . "/RegDB.db";
	my $db = DBI->connect("dbi:SQLite:dbname=$dbfile","","",
		{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

	$db->do("PRAGMA cache_size = 1000000");
	$db->commit;

	my @chrs = (1..22,"X","Y");
	foreach $chr (@chrs) {
		$stch = "chr" . $chr;
		$sth{$stch} = $db->prepare("SELECT DISTINCT objname FROM data, data_" . $stch . "_index WHERE data.id=data_" . $stch . "_index.id AND minX <= ? AND maxX >= ?");
	}
} elsif($TYPE eq "multi") {

	my @chrs = (1..22,"X","Y");
	foreach $chr (@chrs) {
		$stch = "chr" . $chr;
		my $dbfile = $DB_DIR . "/RegDB." . $chr . ".db";
		$dbs{$stch} = DBI->connect("dbi:SQLite:dbname=$dbfile","","",{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

		$dbs{$stch}->do("PRAGMA cache_size = 1000000");
		$dbs{$stch}->commit;
		
		$sth{$stch} = $dbs{$stch}->prepare("SELECT DISTINCT objname FROM data, data_index WHERE data.id=data_index.id AND minX <= ? AND maxX >= ?");
	}
}

open(INF, $QUERY_FILE);
while($line = <INF>) {
	next if($line =~ /^#/);
	chomp($line);
	@temp = split('\s+', $line);


	#Correct for BED 3
	if($temp[3] eq "") {
		$temp[3] = ".";
	}

	#Correct for VCF - 1 based vs 0 based bed
	if($temp[2] =~ /^rs/) {
		$temp[3] = $temp[2];
		$temp[2] = $temp[1];
		$temp[1] = $temp[2] - 1;
	}

	$sth{$temp[0]}->execute($temp[1], $temp[1]);
	my $results = $sth{$temp[0]}->fetchall_arrayref();

	my @output = ();
	foreach $row (@$results) {
		my($res) = @$row;
		push(@output, $res);
	}
	if($#output >= 0) {
		print $temp[0] . "\t" . $temp[1] . "\t" . $temp[2] . "\t" . $temp[3] . "\t";
		print join("+", @output) . "\n";
	} else {
		print $temp[0] . "\t" . $temp[1] . "\t" . $temp[2] . "\t" . $temp[3] . "\t";
		print "0\n";
	}		
}
close(INF);

if($TYPE eq "single") {
	$db->disconnect;
} else {
	foreach $key (keys %dbs) {
		$dbs{$key}->disconnect;
	}
}

