package Regulome::RegulomeDB;
use strict;
use warnings;
BEGIN {
  $RegulomeDB::VERSION = '0.01';
}
use DBI;
use base 'Class::Accessor';
use Data::Dumper;
my @CHRS = (1..22,"X","Y"); # human chromosomes;

#This will load a hash to map PWM names to proper HUGO gene sets.
my $mapPwmtoHugoFile = 'data/RegulomeDB/mapPWMtoHUGO.hash';
my $mapPwmtoHugo = do $mapPwmtoHugoFile || die "Could not open $mapPwmtoHugoFile";

Regulome::RegulomeDB->mk_accessors(qw/dbh dbs sth type dbfile dbdir data_mapping/);
# maybe put in some generic base class...
sub new {
	
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	
    $self->_init_db();
    
    my $mapping = {
        Protein_Binding => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Bound Protein' => 1 },
                                { 'Cell Type' => 2 },
                                { 'Additional Info' => 3 },
                                { 'Reference' => 4 },
                        ],
        },
        Motifs => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Motif' => 1 },
                                { 'Cell Type' => 2 },
                                { 'PWM' => 3 },
                                { 'Reference' => 4 },
                        ],
        },
        Chromatin_Structure => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Cell Type' => 2 },
                                { 'Additional Info' => 3 },
                                { 'Reference' => 4 },
                        ],
        },
        Single_Nucleotides => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Affected Gene' => 1 },
                                { 'Cell Type' => 2 },
                                { 'Additional Info' => 3 },
                                { 'Reference' => 4 },
                        ],
        },
        Related_Data => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Cell Type' => 2 },
                                { 'Annotation' => 3 },
                                { 'Reference' => 4 },
                        ],
        },
        Histone_Modification => {
                columns => [ { 'Method' => 0 },
                                { 'Location' => '' },
                                { 'Histone Mark' => 1 },
                                { 'Cell Type' => 2 },
                                { 'Additional Info' => 3 },
                                { 'Reference' => 4 },
                        ]
        }

    };
    $self->data_mapping($mapping);
    return $self;
}
sub _init_db {
	
	my $self = shift;
	my $sth = {};
	my $cache_statement = "PRAGMA cache_size = 1000000";
	my $dbh; # could be a single connection or a hash

	#Remove single type - can't practically use this
	if ($self->type eq 'single') {
		# this is current not used, don't even have the DB.
		$dbh = DBI->connect("dbi:SQLite:dbname=".$self->dbfile,"","",
		{RaiseError => 1, AutoCommit => 0,
		sqlite_use_immediate_transaction => 0, #temporary fix
		}) or die $DBI::errstr;

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
			$dbh->{$stch} = DBI->connect("dbi:SQLite:dbname=$dbfile","","",
			{RaiseError => 1, AutoCommit => 0,
			sqlite_use_immediate_transaction => 0, #temporary fix
			}) or die $DBI::errstr;

			$dbh->{$stch}->do($cache_statement);
			$dbh->{$stch}->commit;
			$sth->{$stch} = $dbh->{$stch}->prepare("SELECT * FROM (SELECT data_index.minX, data_index.maxX, data.label_id FROM data, data_index WHERE data.id=data_index.id AND minX <= ? AND maxX > ?) AS hits, labels WHERE labels.label_id = 
hits.label_id");
		}
		
	} else {
		die "Please specify 'single' or 'multi' as type parameter.";
	}
	$self->dbs($dbh);
	$self->sth($sth);
	
}

sub score {
	# returns score, given the output of $self->process
	my $self = shift;
	my $results = shift; #Array Ref[ [scores,ref].]
	my $chr = shift || '';
	
        my $score  = {
                score => 7,
        };
        return $score unless @$results;

        for my $record (@$results) {
                my($min, $max, $id1, $id2, $display_table, @fields) = @$record; #probably a field array works better
                my $hit = {};

                for my $col (@{ $self->data_mapping->{$display_table}->{columns} }) {
                        my ($colName, $map) = %$col;
                        $hit->{$colName} = $fields[$map] if $map ne "";
                }
                $hit->{'Location'} = "$chr:$min..$max";
                push@{ $score->{$display_table}->{hits} }, $hit if keys %$hit; #can probably drop this conditional

        }

        $score->{score} = $self->calculate_score($score);

        return $score;
}


#Slower but legible for now
sub calculate_score {

    my $self = shift;
        my $to_score = shift;

        my $score = 7;

        my %TF_factors = ();
        my %PWM_factors = ();
        my %FOOTPRINT_factors = ();
        #FLAGS:
        my ($CHIP, $DNASE, $PWM, $FOOTPRINT, $EQTL, $PWM_matched, $FOOTPRINT_matched) = (0) x 7;

        #Transcription Facotrs
        if(keys %{ $to_score->{Protein_Binding} }) {
                $CHIP = 1;
                foreach(@{ $to_score->{Protein_Binding}->{hits} }) {
                        $TF_factors{$_->{'Bound Protein'}} = 1;
                }
        }

        #DNase
        if(keys %{ $to_score->{Chromatin_Structure} }) {
                foreach(@{ $to_score->{Chromatin_Structure}->{hits} }) {
                        if(exists($_->{Method}) && $_->{Method} eq "DNase-seq") {
                                $DNASE = 1;
                        }
                }
        }

        #PWMs and Footprints
        if(keys %{ $to_score->{Motifs} }) {
                foreach(@{ $to_score->{Motifs}->{hits} }) {
                        if(exists($_->{Method}) && $_->{Method} eq "PWM") {
                                $PWM = 1;
                                @PWM_factors{ keys %{&hPWMtoHUGO( $_->{Motif} )} } = 1;
                        }
                        if(exists($_->{Method}) && $_->{Method} eq "Footprinting") {
                                $FOOTPRINT = 1;
                                @FOOTPRINT_factors{ keys %{&hPWMtoHUGO( $_->{Motif} )} } = 1;
                        }
                }
        }

        #eQTLs (also considering dsQTLs as equivalent)
        if(keys %{ $to_score->{Single_Nucleotides} }) {
                foreach(@{ $to_score->{Single_Nucleotides}->{hits} }) {
                        if(exists($_->{Method}) && ( $_->{Method} eq "eQTL" || $_->{Method} eq "dsQTL" )) {
                                $EQTL = 1;
                        }
                }
        }

        # Match PWMs and Footprints to TFs
        for my $tfkey (keys %TF_factors) {
                if( exists $PWM_factors{ $tfkey } ) {
                        $PWM_matched = 1;
                }
                if( exists $FOOTPRINT_factors{ $tfkey } ) {
                        $FOOTPRINT_matched = 1;
                }
        }

        #Now the scoring
        if($CHIP == 1 || $DNASE == 1 || $PWM == 1 || $FOOTPRINT == 1 || $EQTL == 1) {
                $score = 6;
        }

        if($CHIP == 1 || $DNASE == 1) {
                $score = 5;
        }

        if($CHIP == 1 && $DNASE == 1) {
                $score = 4;
        }

        if($CHIP == 1 && $PWM_matched == 1) {
                $score = "3b";
        }

        if($CHIP == 1 && $DNASE == 1 && $PWM == 1) {
                $score = "3a";
        }
        
        if($CHIP == 1 && $DNASE == 1 && $PWM == 1 && $PWM_matched == 1) {
                $score = "2c";
        }
                         
        if($CHIP == 1 && $DNASE == 1 && $PWM == 1 && $FOOTPRINT == 1) {
                $score = "2b";
        }
        
        if($CHIP == 1 && $DNASE == 1 && $PWM == 1 && $PWM_matched == 1 && $FOOTPRINT == 1 && $FOOTPRINT_matched == 1) {
                $score = "2a";
        }
                                
        if($EQTL == 1) {
                if($DNASE == 1 || $CHIP == 1) {
                        $score = "1f";
                }
                if($CHIP == 1) {
                        if($PWM_matched == 1) {
                                $score = "1e";
                        }
                        if($PWM == 1 && $DNASE == 1) {
                                $score = "1d";
                        }
                        if($PWM_matched == 1 && $DNASE == 1) {
                                $score = "1c";
                        }
                        if($PWM == 1 && $FOOTPRINT == 1 && $DNASE == 1) {
                                $score = "1b";
                        }
                        if($PWM_matched == 1 && $FOOTPRINT_matched == 1 && $DNASE == 1) {
                                $score = "1a";
                        }
                }
        }
                 
	return $score;
}

sub hPWMtoHUGO {
	my $old_factor_name = shift;
	my %results = ();
	my @split_names = split(/[:=]/,$old_factor_name);
	foreach(@split_names) {
		if($_ ne "") {
			@results{ keys %{$mapPwmtoHugo->{uc($_)}} } = 1;
		}
	}
	$results{$old_factor_name} = 1;
  	return \%results;
    
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
