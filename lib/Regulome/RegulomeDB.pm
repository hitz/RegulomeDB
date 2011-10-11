package RegulomeDB;
use strict;
use warnings;
BEGIN {
  $RegulomeDB::VERSION = '0.01';
}
use DBI;
use base 'Class::Accessor';
use Data::Dumper;
my @CHRS = (1..22,"X","Y"); # human chromosomes;

RegulomeDB->mk_accessors(qw/dbh dbs sth type dbfile dbdir/);
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
	my $dbh; # could be a single connection or a hash
	if ($self->type eq 'single') {
		# this is current not used, don't even have the DB.
		$dbh = DBI->connect("dbi:SQLite:dbname=".$self->dbfile,"","",
		{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

		$dbh->do($cache_statement);
		$dbh->commit;
		for my $chr (@CHRS) {
			my $stch = "chr" . $chr;
			$sth->{$stch} = $dbh->prepare_cached("SELECT DISTINCT objname,objref,minX,maxX FROM data, data_" . $stch . "_index WHERE data.id=data_" . $stch . "_index.id AND minX <= ? AND maxX >= ?");
		}
	} elsif ($self->type eq 'multi') {
		$dbh = {}; # hash by chromosomes;
		for my $chr (@CHRS) {
			my $stch = "chr" . $chr;
			my $dbfile = $self->dbdir . "/RegDB." . $chr . ".db";
			$dbh->{$stch} = DBI->connect("dbi:SQLite:dbname=$dbfile","","",{RaiseError => 1, AutoCommit => 0}) or die $DBI::errstr;

			$dbh->{$stch}->do($cache_statement);
			$dbh->{$stch}->commit;
			$sth->{$stch} = $dbh->{$stch}->prepare("SELECT DISTINCT objname,objref,minX,maxX FROM data, data_index WHERE data.id=data_index.id AND minX <= ? AND maxX >= ?");
		}
		
	} else {
		die "Please specify 'single' or 'multi' as type parameter.";
	}
	$self->dbs($dbh);
	$self->sth($sth);
	
}
sub full_score () {
	# this might be slower
	# returns score, given the output of $self->process
	my $self = shift;
	my $results = shift; #Array Ref[ [scores,ref, min, max].]
	
	my $score  = {
		score => 5, 
	};
	return $score unless @$results;
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

	for my $record (@$results) {
		my ($item, $ref, $min, $max) = @$record;
		my ($group, $category, $class, @cond) = ('not_found','','', ()); # reset
		($group, $category, $class, @cond) = split('_',$item);
		my $arr;
		# not happy with this below
		if ($class) { 
		    $arr = $score->{$group}->{$class}->{$category} || [];
			push @$arr, ($ref, $min, $max, @cond);
			$score->{$group}->{$class}->{$category} = $arr if @$arr
		} else {
	        $arr = $score->{$group}->{$category} || [];			
			push @$arr, ($ref, $min, $max, @cond);
			$score->{$group}->{$category} = $arr if @$arr
		}
		
	}
	
	my $pwmmatched = 0;
	my $fpmatched = 0;
	for my $key (keys %{$score->{TF}}) {
		if(exists $score->{PWM}->{$key}) {
			$pwmmatched = 1;
		}
		if(exists $score->{FP}->{$key}) {
			$fpmatched = 1;
		}
	}
	
	$score->{score} = 4;
	if(keys %{ $score->{TF} }|| keys % {$score->{DNase}}) {
		$score->{score} = 3;
	} 

	if(keys %{ $score->{TF} } && keys %{ $score->{DNase} }) {
		$score->{score} = 2;
	} 

	if(keys %{ $score->{TF} } && keys %{ $score->{DNase} } && keys %{ $score->{PWM} }) {
		$score->{score} = ($pwmmatched ? 
			(keys %{ $score->{FP}} ? 
				(keys %{ $score->{eQTL}} ?  
					($fpmatched ? 
						1.1 : 1.2)  : 1.3 ) : 1.4 ) : 1.5);
	} 

	#print STDERR Dumper($score);
	return $score;
		
}
sub score() {
	# returns score, given the output of $self->process
	my $self = shift;
	my $scores = shift; #Array Ref[ [scores,ref].]
	
	return 5 unless @$scores; # zero hits

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
	my %footprints = ();
	my $eqtl = 0;
	my $manual = 0; ## no score for this yet
	my %chips = ();
	
	for my $pair (@$scores) {
		my ($item, $ref, $rest) = @$pair; #safe guard in case we later return more columns!
		if($item =~ /PWM_(\w+)/) {
			$PWMs{$1}++;
		} elsif($item =~ /DNase/) {
			$DNase = 1;
		} elsif($item =~ /FP_.+_(\w+)/) {
			$footprints{$1}++;
		} elsif($item =~ /eQTL/) {
			$eqtl = 1;
		} elsif($item =~ /MANUAL/) {
			$manual = 1;
		} elsif($item =~ /^TF_.*?_([^\s_]+)/) {
			#$item =~ s/_.*//; fix regex above
			$chips{$1}++;
		}
	}
	
	my $pwmmatched = 0;
	my $fpmatched = 0;
	for my $key (keys %chips) {
		if(exists $PWMs{$key}) {
			$pwmmatched = 1;
		}
		if(exists $footprints{$key}) {
			$fpmatched = 1;
		}
	}
	
	my $score = 4;
	if(%chips || $DNase == 1) {
		$score = 3;
	} 

	if(%chips && $DNase == 1) {
		$score = 2;
	} 

	if(%chips && $DNase == 1 && %PWMs) {
		$score = ($pwmmatched ? 
			(%footprints ? 
				($eqtl ?  
					($fpmatched ? 
						1.1 : 1.2)  : 1.3 ) : 1.4 ) : 1.5);
	} 

	return $score;
	
}
sub process(){
	my $self = shift;
	my $coords = shift; # [chr, position]
	my $sth = $self->sth->{$coords->[0]} || die "could not find chromosome: $coords->[0]";
	$sth->execute($coords->[1],$coords->[1]);
	my $results = $sth->fetchall_arrayref();
	
	return $results;
}

sub DESTROY { 
	my $self = shift;
	if($self->type eq "single") {
		$self->dbh->disconnect;
	} else {
		for my $key (keys %{$self->dbs}) {
			$self->dbs->{$key}->disconnect if $self->dbs->{$key};
		}
	}
	
}
1;
