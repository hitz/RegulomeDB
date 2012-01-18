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

#This will load a hash to map PWM names to proper HUGO gene sets
my $mapPwmtoHugoFile = 'data/RegulomeDB/mapPWMtoHUGO.hash';
my $mapPwmtoHugo = do $mapPwmtoHugoFile || die "Could not open $mapPwmtoHugoFile";

Regulome::RegulomeDB->mk_accessors(qw/dbh dbs sth type dbfile dbdir data_mapping/);
# maybe put in some generic base class...
sub new {
	
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	
    $self->_init_db();
    
    my $mapping = {
     	TF  => {
     		regex => '(TF)_(.+)_(.+)_{0,1}(.*)',
     		columns => [ { 'Method' => 'ChIP-Seq' },
     				     { 'Location' => '' },
     				     { 'Bound Protein' => 2 }, 
     				     { 'Cell Type' => 1 },
     				     { 'Additional Info' => [3,'rest'] },
     				     { 'Reference' => '' },
     				    ],		     
     	},
    	PWM => {
    		regex => '(PWM)_(.+)',
      		columns => [ { 'Method' => 'PWM'},
     				     { 'Location' => '' },
     				     { 'Motif' => 1 }, 
     				     { 'Cell Type' => ''},
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	FP  => {
    		regex => '(FP)_(.+)_(.+)',
      		columns => [ { 'Method' => 'Footprinting'},
     				     { 'Location' => '' },
     				     { 'Motif' => 2 }, 
     				     { 'Cell Type' => 1},
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	VAL => {
    		regex => '(VAL)_(.+)_(.+)_{0,1}(.*)',
      		columns => [ { 'Method' => 'Validated SNP'},
     				     { 'Location' => '' },
     				     { 'Affected Gene' => 2 }, 
     				     { 'Cell Type' => 1 },
     				     { 'Additional Information' => [3,'rest'] },
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	eQTL =>  {
    		regex => '(eQTL)_(.+)_(.+)',
      		columns => [ { 'Method' => 'eQTL'},
     				     { 'Location' => '' },
     				     { 'Affected Gene' => 2 }, 
     				     { 'Cell Type' => 1 },
     				     { 'Additional Information' => '' },
     				     { 'Reference' => '' },
     				    ],		        		
    	},
     	DNase => {
    		regex => '^(DNase)_(.+)_{0,1}(.*)',
      		columns => [ { 'Method' => 'DNase hypersensitivity'},
     				     { 'Location' => '' },
     				     { 'Cell Type' => 1 },
     				     { 'Additional Information' => [2,'rest'] },
     				     { 'Reference' => '' },
     				    ],		        		
    	},
     	MANUALTF  => {
     		regex => '\((.*)\)_\((.*)\)_\((.*)\)_MANUALTF',
     		columns => [ { 'Method' => "(0)" },
     				     { 'Location' => '' },
     				     { 'Bound Protein' => "(2)" }, 
     				     { 'Cell Type' => "(1)" },
     				     { 'Additional Info' => '' },
     				     { 'Reference' => '' },
     				    ],		     
     	},
    	MANUALFP  => {
    		regex => '\(.*footprint(.*)\)_\((.*)\)_\((.*)\)_MANUAL',
      		columns => [ { 'Method' => "(0)"},
     				     { 'Location' => '' },
     				     { 'Motif' => "(2)" }, 
     				     { 'Cell Type' => "(1)"},
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	MANUALPWM  => {
    		regex => 'MOTIF_\((.*)\)_MANUAL',
      		columns => [ { 'Method' => 'PWM'},
     				     { 'Location' => '' },
     				     { 'Motif' => "(1)" }, 
     				     { 'Cell Type' => ''},
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	MANUALSNV =>  {
    		regex => 'SNV_\((.*)\)_\((.*)\)_\((.*)\)_MANUAL',
      		columns => [ { 'Method' => ''},
     				     { 'Location' => '' },
     				     { 'Affected Gene' => "(2)" }, 
     				     { 'Cell Type' => "(1)" },
     				     { 'Additional Information' => "(3)" },
     				     { 'Reference' => '' },
     				    ],		        		
    	},
    	Other => {
    		regex => '(.*)_(MANUAL|MANUALTF)$',
    		columns => [ { 'Method' => "(0)"},
    		     		 { 'Location' => '' },   		
    				 { 'Cell Type' => "(1)" },
    				 { 'Annotation' => "(2)" },
    				 { 'Reference' => '' },
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
	my $chr = shift;
	
	my $score  = {
		score => 7, 
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

	my $factors = {'Bound Protein' => 1, 'Motif' => 2};
    
	for my $record (@$results) {
		my ($item, $ref, $min, $max) = @$record;
		my $record_has_hit = 0;
		for my $type (keys %{ $self->data_mapping }) {
			# needs to be an array of hits, but a hash of factors
			my $regex = $self->data_mapping->{$type}->{regex};
			my $sc = $score->{$type} || { hits => [], factors => {} };
			if ($item =~ /$regex/) {
				my $hit = {};
				
				# BEGIN THE UGLY PARSE-O-MATIC
				my @f = split('_', $item);
				my @f_paren = split('\)_\({0,1}', $item);
				for my $col (@{ $self->data_mapping->{$type}->{columns} }) {
					my ($colName, $map) = %$col;
					my $map_paren;
					
					if ($colName eq 'Location') {
						$hit->{$colName} = "$chr:$min..$max";
					} elsif ($colName eq 'Reference') {
						$hit->{$colName} = $ref;
						# further processing later
					} elsif (!$map)  {
						$hit->{$colName} = '';
					} elsif (ref($map) eq 'ARRAY') {
						$hit->{$colName} = join(" ",@f[$map->[0] .. $#f]);
					} elsif (($map_paren) = $map =~ /\((\d+)\)/) {
						($hit->{$colName}) = $f_paren[$map_paren] =~ /\(?(.*)/;
						$hit->{$colName} =~ s/_/ /g;
						$hit->{$colName} =~ s/(\w+)/\u\L$1/g;
					} elsif ($map =~ /\d+/) {
						if (exists $factors->{$colName}) {
							for my $alt (&hPWMtoHUGO($f[$map])) {
								$sc->{factors}->{$alt}++;
							}
						}						
						$hit->{$colName} = $f[$map]; # replace with alt hit?
					} else {
						$hit->{$colName} = $map;
					}
						
				}
				push @{ $sc->{hits} }, $hit if keys %$hit;
				$score->{$type} = $sc if @{ $sc->{hits} };
				$record_has_hit++ if keys %$hit; #Keeping track of hits for Other MANUAL type				
			}
		}
		pop(@{ $score->{Other}->{hits} }) if ($record_has_hit > 1); #If the record has a hit then remove from Other
	}
	
	my $pwmmatched = 0;
	my $fpmatched = 0;
	for my $key (keys %{$score->{TF}->{factors}}) {
		if(exists $score->{PWM} && exists $score->{PWM}->{factors}->{$key}) {
			$pwmmatched = 1;
		}
		if(exists $score->{FP} && exists $score->{FP}->{factors}->{$key}) {
			$fpmatched = 1;
		}
	}
	
#	$score->{score} = 4;
#	if(keys %{ $score->{TF}->{factors} }|| keys %{ $score->{DNase} }) {
#		$score->{score} = 3;
#	} 
#
#	if(keys %{ $score->{TF}->{factors} } && keys %{ $score->{DNase} }) {
#		$score->{score} = 2;
#	} 
#
#	if(keys %{ $score->{TF}->{factors} } && keys %{ $score->{DNase} } && keys %{ $score->{PWM} }) {
#		$score->{score} = ($pwmmatched ? 
#			(keys %{ $score->{FP}} ? 
#				(keys %{ $score->{eQTL}} ?  
#					($fpmatched ? 
#						1.1 : 1.2)  : 1.3 ) : 1.4 ) : 1.5);
#	} 

	my $chip_count = keys(%{ $score->{TF}->{factors} });
	my $pwm_count = keys(%{ $score->{PWM} });
	my $footprint_count = keys(%{ $score->{FP} });
	my $eqtl_count = keys(%{ $score->{eQTL} });
	my $dnase_count = keys(%{ $score->{DNase} });
	$score->{score} = &calculate_score($chip_count, $dnase_count, $pwm_count, $footprint_count, $eqtl_count, $pwmmatched, $fpmatched);

	return $score;
		
}
sub score() {
	# returns score, given the output of $self->process
	my $self = shift;
	my $scores = shift; #Array Ref[ [scores,ref].]
	
	return 7 unless @$scores; # zero hits

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
		if($item =~ /(PWM)_(.+)/) {
			@PWMs{ &hPWMtoHUGO($2) } = 1;
		} elsif($item =~ /DNase/) {
			$DNase = 1;
		} elsif($item =~ /(FP)_(.+)_(.+)/) {
			@footprints{ &hPWMtoHUGO($3) } = 1;
		} elsif($item =~ /eQTL/) {
			$eqtl = 1;
		} elsif($item =~ /MANUAL/) {
			$manual = 1;
		} elsif($item =~ /^(TF)_(.+)_(.+)_{0,1}(.*)/) {
			@chips{ &hPWMtoHUGO($3) } = 1;
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

#	my $score = 4;
#	if(%chips || $DNase == 1) {
#		$score = 3;
#	} 
#
#	if(%chips && $DNase == 1) {
#		$score = 2;
#	} 
#
#	if(%chips && $DNase == 1 && %PWMs) {
#		$score = ($pwmmatched ? 
#			(%footprints ? 
#				($eqtl ?  
#					($fpmatched ? 
#						1.1 : 1.2)  : 1.3 ) : 1.4 ) : 1.5);
#	} 

	my $chip_count = keys(%chips);
	my $pwm_count = keys(%PWMs);
	my $footprint_count = keys(%footprints);
	my $score = &calculate_score($chip_count, $DNase, $pwm_count, $footprint_count, $eqtl, $pwmmatched, $fpmatched);

	#print STDERR "CHIPS: ", Dumper %chips;
	#print STDERR "PWMS: ", Dumper %PWMs;
	#print STDERR "FPS", Dumper %footprints;
	return $score;
	
}


#Slower but legible for now
sub calculate_score {
    my($chip, $DNase, $PWM, $footprint, $eqtl, $pwmmatched, $fpmatched) = @_;

    my $score = 7;

    if($chip >= 1 || $DNase >= 1 || $PWM >= 1 || $footprint >= 1 || $eqtl >= 1) {
        $score = 6;
    }

    if($chip >= 1 || $DNase >= 1) {
        $score = 5;
    }

    if($chip >= 1 && $DNase >= 1) {
        $score = 4;
    }

    if($chip >= 1 && $pwmmatched >= 1) {
        $score = "3b";
    }

    if($chip >= 1 && $DNase >= 1 && $PWM >= 1) {
        $score = "3a";
    }

    if($chip >= 1 && $DNase >= 1 && $PWM >= 1 && $pwmmatched >= 1) {
        $score = "2c";
    }

    if($chip >= 1 && $DNase >= 1 && $PWM >= 1 && $footprint >= 1) {
        $score = "2b";
    }

    if($chip >= 1 && $DNase >= 1 && $PWM >= 1 && $pwmmatched >= 1 && $footprint >= 1 && $fpmatched >= 1) {
        $score = "2a";
    }
    
    if($eqtl >= 1) {
        if($DNase >= 1 || $chip >= 1) {
            $score = "1f";
        }
        if($chip >= 1) {
            if($pwmmatched >= 1) {
                $score = "1e";
            }
            if($PWM >= 1 && $DNase >= 1) {
                $score = "1d";
            }
            if($pwmmatched >= 1 && $DNase >= 1) {
                $score = "1c";
            }
            if($PWM >= 1 && $footprint >= 1 && $DNase >= 1) {
                $score = "1b";
            }
            if($pwmmatched >= 1 && $fpmatched >= 1 && $DNase >= 1) {
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
  	return keys %results;
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
