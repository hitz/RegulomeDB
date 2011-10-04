package RegulomeDB;
BEGIN {
  $RegulomeDB::VERSION = '0.01';
}
use DBI;
use base 'Class::Accessor';
use List::Flatten;
use Data::Dumper;
@CHRS = (1..22,"X","Y"); # human chromosomes;

RegulomeDB->mk_accessors(qw/dbh sth type dbfile dbdir/);
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
	if ($self->type eq 'single') {
		my $dbh = DBI->connect("dbi:SQLite:dbname=".$self->dbfile,"","",
		{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

		$dbh->do($cache_statement);
		$dbh->commit;
		for my $chr (@CHRS) {
			my $stch = "chr" . $chr;
			$sth->{$stch} = $dbh->prepare_cached("SELECT DISTINCT objname FROM data, data_" . $stch . "_index WHERE data.id=data_" . $stch . "_index.id AND minX <= ? AND maxX >= ?");
		}
	} elsif ($self->type eq 'multi') {
		for $chr (@CHRS) {
			my $stch = "chr" . $chr;
			my $dbfile = $self->dbdir . "/RegDB." . $chr . ".db";
			my $dbh = {}; # hash by chromosomes;
			$dbh->{$stch} = DBI->connect("dbi:SQLite:dbname=$dbfile","","",{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

			$dbh->{$stch}->do($cache_statement);
			$dbh->{$stch}->commit;
			$sth->{$stch} = $dbh->{$stch}->prepare("SELECT DISTINCT objname FROM data, data_index WHERE data.id=data_index.id AND minX <= ? AND maxX >= ?");
		}
		
	} else {
		die "Please specify 'single' or 'multi' as type parameter.";
	}
	$self->dbh($dbh);
	$self->sth($sth);
	
}

sub score() {
	# returns the hit names and score
	my $self = shift;
	my $scores = shift; #Array Ref of scores
	return (["None"], 5) unless $scores->[0];

	#scoring scheme
	# 1 -> known to cause heteroallelic binidng
	# 1.1 -> ChIP_seq + motif + footprints + DNase + eQTL
	# 1.2 -> ChIP_seq + motif + footprint + DNase + eQTL
	# 1.3 -> ChIP_seq + motif + footprint + DNase
	# 1.4 -> ChIP_seq + motif + DNase
	# 1.5 -> ChIP_seq + non-matched motif + DNase
	# 2 -> ChIP_seq + DNase
	# 3 -> ChIP_seq or DNase
	# 4 -> other
	
	
	my %PWMs = ();
	my $DNase = 0;
	my $footprint = 0;
	my %footprints = ();
	my $eqtl = 0;
	my $manual = 0;
	my $chip = 0;
	my %chips = ();
	
	for $item (@${scores->[0]}) {
		if($item =~ /PWM_(\w+)/) {
			$PWMs{$item}++;
		} elsif($item =~ /DNase/) {
			$DNase = 1;
		} elsif($item =~ /FP_.+_(\w+)/) {
			$footprints{$1}++;
		} elsif($item =~ /eQTL/) {
			$eqtl = 1;
		} elsif($item =~ /MANUAL/) {
			$manual = 1;
		} elsif($item =~ /^TF_.*?_(\w+)/) {
			#$item =~ s/_.*//; fix regex above
			$chips{$1}++;
		}
	}
	
	$pwmmatched = 0;
	$fpmatched = 0;
	foreach $key (keys %chips) {
		if(exists $PWMs{$key}) {
			$pwmmatched = 1;
		}
		if(exists $footprints{$key}) {
			$fpmatched = 1;
		}
	}
	
	$score = 4;
	if(%chips || $DNase == 1) {
		$score = 3;
	} 

	if(%chips && $DNase == 1) {
		$score = 2;
	} 

	if(%chips && $DNase == 1 && %PWMs) {
		$score = ($pwmmatched ? 
					($footprint ? 
						($eqtl ?
						   ($fpmatched ? 1.1 : 1.2 )
				     : 1.4 ) : 1.3 ) : 1.5);
	} 

	return ($scores->[0], $score);
	
}
sub process(){
	my $self = shift;
	my ($chr, $min, $max)  = @_[0..2];
	$max = $min unless $max =~ /^\d+$/;
	my $sth = $self->sth->{$chr} || die "could not find chromosome $chr";
	$sth->execute($min, $max);
	my $results = $sth->fetchall_arrayref();
	
	return $results->[0];
}

sub check_coord() {
	
	my $self = shift;
	my $input = shift;
	chomp($input); ## shouldn't have any trailing \n but just in case
	$input =~ s/^\s+//;
	# try to guess the format
	
	my $format = "Unknown";
	my ($chr, $min, $max);
	if ($input =~ /(chr|^)(\d+|[xXyY])(:|\s+)(\d+)(\.\.|-|\s+)(\d+)(.*)/) {
		# nn:nnnn..nnnn
		# any generic or BED chromsome(delim)min(delim)max
		# 1 based input, subtract
		$chr = $2; 	
		$min = $4;
		$max = $6;
		my $base = 0;
		$format = 'BED - 0 Based';
		if ($3 =~ /[:-_]/ || $5 =~ /\S/) {
			$format = 'Generic - 1 Based';
			$base =1;
			$min -= $base;
			$max -= $base;
		}
	} else {
		@f = split('\s+',$input);
		if (@f>=8) {
		# could be VCF or GFF.
			$chr = $f[0];
			if ($f[1] =~ /(^\d+$)/ && $f[3] !~ /^\d+$/ && $f[4] !~ /^\d+$/) {
				# looks like VCF
				$min = $1-1;
				$max = $min;
				$format = 'VCF - 1 based';
			} elsif ($f[4] =~ /(^\d+$)/) {
				# looks like GFF
				$min = $1-1;
				$max = $1-1 if $f[5] =~ /(^\d+$)/;
				$format = 'GFF - 1 based';
			} else {
				die "I thought this was VCF or GFF but I couldn't parse it: $input";
			}
		} else {
			die "format: $input not recognized";
		}
	}
	die ("format: $format invalid chromosome id: ($chr) [$input]") unless $chr =~ /(chr|^)(\d+|[xXyY])/;
	$chr = "chr$chr" unless $chr =~ /^chr/;
	die ("format: $format invalid min coordinate $min [$input]") unless $min =~ /^(\d+)$/;
	return ($format, $chr, $min, $max);
	
}

sub DESTROY {
	my $self = shift;
	if($self->type eq "single") {
		$self->dbh->disconnect;
	} else {
		for $key (keys %{$self->dbh}) {
		$self->dbh->{$key}->disconnect;
	}
}
	
}
1;