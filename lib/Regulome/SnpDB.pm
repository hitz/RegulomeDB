package SnpDB;
use strict;
use warnings;
BEGIN {
  $SnpDB::VERSION = '0.01';
}
use DBI;
use base 'Class::Accessor';
use Data::Dumper;
my @CHRS = (1..22,"X","Y"); # human chromosomes;

SnpDB->mk_accessors(qw/dbs sth type dbfile_all dbfile dbfile_common dbdir/);
# maybe put in some generic base class...
sub new {
	
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	
    $self->_init();
    return $self;
}
sub _init {
	
	my $self = shift;
	my $sth = {};
	my $cache_statement = "PRAGMA cache_size = 1000000";
	$self->dbs({ common => undef,
		         all    => undef,
	});
	my $dbfile_common = $self->dbfile_common || $self->dbfile_all || $self->dbfile;
	if (!$self->type || $self->type eq 'single') {
		# common SNPS
		my $dbh = DBI->connect("dbi:SQLite:dbname=".$self->dbfile_common,"","",
		{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

		$dbh->do($cache_statement);
		$dbh->commit;
		for my $chr (@CHRS) {
			my $stch = "chr" . $chr;
			$sth->{$stch} = $dbh->prepare_cached("SELECT chrom, position FROM data, data_" . $stch . "_index  WHERE data.id=data_" . $stch . "_index.id AND minX >= ? AND maxX <= ?");
		}
		$self->dbs->{common} = $dbh;
	} elsif ($self->type eq 'multi') {
		die "Multi-type SNP database not currently supported";
		
	}
	my $dbh2 = DBI->connect("dbi:SQLite:dbname=".$self->dbfile_all,"","",
		{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

	$dbh2->do($cache_statement);
	$dbh2->commit;	
	$sth->{rsid2pos} = $dbh2->prepare_cached("SELECT chrom, position FROM data WHERE rsid = ?");
	$sth->{pos2rsid} = $dbh2->prepare_cached("SELECT rsid FROM data WHERE chrom == ? AND position == ?");
	$self->dbs->{all} = $dbh2;

	$self->sth($sth);
	
}

sub getSNPbyRange(){
	my $self = shift;
	my ($chr, $min, $max)  = @_[0..2];
	$max = $min unless $max =~ /^\d+$/;
	my $sth = $self->sth->{$chr} || die "could not find chromosome $chr";
	$sth->execute($min, $max);
	my $results = $sth->fetchall_arrayref();
	
	return $results; #[ [chr, pos],[] ...]
}

sub getSNPbyRsid(){
	my $self = shift;
	my $rsid = shift;
	
	my $sth = $self->sth->{rsid2pos};
	$sth->execute($rsid);
	my $results = $sth->fetchall_arrayref();
	
	return $results->[0]; # [chr, position] OR empty)
}

sub getRsid() {
	my $self = shift;
	my $coords = shift; ## [ chr, pos ]
	
	my $sth = $self->sth->{pos2rsid};
	$sth->execute($coords->[0],$coords->[1]);
	my $results = $sth->fetchall_arrayref();
	
	return $results->[0]->[0];	
	
}
sub DESTROY { 
	my $self = shift;
	$self->dbs->{all}->disconnect if $self->dbs->{all};
	$self->dbs->{common}->disconnect if $self->dbs->{common};
	
}
1;
