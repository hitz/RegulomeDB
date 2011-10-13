package Regulome;
use Mojo::Base 'Mojolicious';
use lib 'lib';
use Regulome::RegulomeDB;
use Regulome::SnpDB;

# This method will run once at server start
sub startup {
	my $self = shift;

	#$self->log->level('error');
	my $regDB = Regulome::RegulomeDB->new(
								 {
								   type  => 'multi',
								   dbdir => 'data/RegulomeDB'
								 }
	);

	my $snDB = Regulome::SnpDB->new(
						   {
							 type          => 'single',
							 dbfile_all    => 'data/SnpDB/dbSNP132.db',
							 dbfile_common => 'data/SnpDB/dbSNP132Common.db',
						   }
	);

	$self->helper( 'rdb'   => sub { return $regDB } );
	$self->helper( 'snpdb' => sub { return $snDB } );

	$self->helper(
		'check_coord' => sub {

			my $self  = shift;
			my $input = shift;
			chomp($input);    ## shouldn't have any trailing \n but just in case
			$input =~ s/^\s+//;

			# try to guess the format

			my $format = "Unknown";
			my ( $chr, $min, $max ) = ('None',-1,-1);
			if ( $input =~ /^\s*([rs]s\d+)\s*$/ ) { 
                # note that "big formats" might also have rs# in them!
				# dbsnp ID, not sure if ss#### is used in our DB
				$format = 'dbSNPid';
				my $dbSNPid = $1;
				return ( $format, [ $self->snpdb->getSNPbyRsid($dbSNPid) ] );

			} elsif ( $input =~ /(chr|^)(\d+|[xy])(:|\s+)(\d+)(\.\.|-|\s+)(\d+)(.*)/i ) {

				# BED chromsome(space)min(space)max
				$chr = $2;
				$min = $4;
				$max = $6; 
				# ch:nnnn..mmmm - or ch:nnnn-mmmm # 1 based input, subtract
				if ( $3 =~ /[:-_]/ || $5 =~ /\S/ ) {
					$format = 'Generic - 1 Based';
					$min--;
					$max--; 
				} else {
					$format = 'BED - 0 Based';
					$max--; #EXCLUSIVE			
				}
			} else {
				my @f = split( '\s+', $input );
				if ( @f >= 8 ) {

					# could be VCF or GFF.
					$chr = $f[0];
					if (    $f[1] =~ /(^\d+$)/
						 && $f[3] !~ /^\d+$/
						 && $f[4] !~ /^\d+$/ )
					{

						# looks like VCF
						$min    = $1 - 1;
						$max    = $min;
						$format = 'VCF - 1 Based';
					} elsif ( $f[3] =~ /(^\d+$)/ ) {

						# looks like GFF
						$min    = $1 - 1;
						$max    = $1 - 1 if $f[4] =~ /(^\d+$)/;
						$format = 'GFF - 1 Based';
					} else {
						return('ERROR', [["I thought this was VCF or GFF but I couldn't parse it:", $input]] );
					}
				} else {
					return("ERROR", [["Input not recognized", $input]]);
				}
			}
			return("ERROR", [["format: $format invalid chromosome id: ($chr)",$input]]) unless $chr =~ /(chr|^)(\d+|[xy])/i;
			$chr = "chr$chr" unless $chr =~ /^chr/;
			$chr =~ s/([xy])/\u$1/;
			return("ERROR", [["format: $format invalid min coordinate $min", $input]]) 
				unless $min =~ /^(\d+)$/;

			if ( $min > $max ) {
				return ("ERROR", [["Min ($min) cannot be greater than max ($max) in range!",$input]]);
			} elsif ( $max > $min ) {
				
				$self->app->log->debug("WARNING: 2-bp range [$chr, $min, $max] detected, did you mean to specify only a single bp?")
				   if($max == $min+1);
				return ( $format, $self->snpdb->getSNPbyRange( [$chr, $min, $max+1] ) );
				# 1 is added back because the SNPS are stored as 1-base intervals.
			}
			return ( $format, [ [$chr, $min] ] );

		}
	);

	# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
	$self->plugin('PODRenderer');
	$self->secret("fortnight");
	$self->plugin('RequestTimer');
	

	# Routes
	my $r = $self->routes;

	# Normal route to controller
	$r->route('/welcome')->to('example#welcome');

	$r->any( '/search' => sub {} );
	$r->any( '/about' => sub {} );
	$r->any( '/help' => sub {} );

	$r->any( '/' => sub { shift->render({template => 'search'}) } );
	$r->any( '/index' => sub { shift->render({template => 'search'}) } );
	$r->any(
		'/snp/:id/' => sub {
			my $self = shift;
			my $rsid = $self->param('id');
			my $coord = $self->snpdb->getSNPbyRsid($rsid);
			$self->to('not found') unless $coord;
			
			# following needs to move to controller
		    my $res = $self->rdb->process($coord);

			my @dataTable = ();
			my @dtColumns = ({ sTitle => 'Datatype', sClass => 'aligncenter'},
							 { sTitle => 'TF', sClass => 'aligncenter'},
							 { sTitle => 'Location', sClass => 'aligncenter'},
							 { sTitle => 'Souce', sClass => 'aligncenter'}, 
							 { sTitle => 'Additional Info (cell type, condition)', sClass => 'aligncenter'});


			my $score = $self->rdb->score($res);
			for my $record (@$res) {
				my ($item, $ref, $min, $max) = @$record;
				my ($group, $category, $class, @cond) = ('not_found','','', ()); # reset
				($group, $category, $class, @cond) = split('_',$item);
				my $loc = $coord->[0]."$min"."..".$max;
				if ($class) {
					if($group eq 'MANUAL') {
						push @dataTable, [$group, "", $loc, $ref, join(" ",($class,$category,@cond))];
						
					} else {
						push @dataTable, [$group, $class, $loc, $ref, join(", ",($category,@cond))];						
					}
				} elsif ($group eq 'PWM') {
					push @dataTable, [$group, "", $loc, $ref, ""];
				} else {
					push @dataTable, [$group, "", $loc, $ref, $category];					
				}
				
			}
		     	        		    
			$self->stash({snpid => $rsid,
						  score => $score,
						  chr  => $coord->[0],
						  pos  => $coord->[1],
						  snpDataTable => Mojo::JSON->new->encode({aaData => \@dataTable,
																  aoColumns => \@dtColumns,
																  bJQueryUI => 'true',
																  bFilter   => 0,
																  aaSortingFixed => [[0,'asc']],
						  })
			});
		}
	);

	$r->get( 
	    '/running' => sub { shift->render({template => 'search'})
	    });
	    
	$r->post(
		'/running' => sub {

			# all this could move into controller
			my $self = shift;
			my $data;
			if ( $data = $self->param('data') ) {
				$self->app->log->debug('Processing manual data...');
			} elsif ( $data =
					  $self->req->upload('file_data')->asset->get_chunk() )
			{

				# this needs to be changed for "real" 3M SNP files
				$self->app->log->debug("Processing data from file...");
			}

			$data =~ s/(.+\n)([^\n]*)$/$1/;    # trim trailing
			my $remnant = $2;                       # we will need this later
			my $input = [ split( "\n", $data ), $remnant ];# just process it for now.
			#$self->stash( coords  => $input );
			$self->stash( remnant => '' );

	        # below should go in some helper module or DB somewhere.
	        my $BROWSE_PADDING = 10000;
	        my $externalURL = {
	        	ENSEMBL => 'http://uswest.ensembl.org/Homo_sapiens/Location/View?r=',
	        # must append X:50020991-50040991
	        	dbSNP   => 'http://www.ncbi.nlm.nih.gov/projects/SNP/snp_ref.cgi?rs=',
	        # must append DBSNP id
	        	UCSC    => 'http://genome.ucsc.edu/cgi-bin/hgTracks?org=Human&db=hg19&position=chr',
	        # must append X:50020991-50040991
	        };
	        my $ensembleImgURL = 'http://uswest.ensembl.org/Homo_sapiens/Component/Location/Web/ViewTop?r=';
	        # must append X:50030991;export=png
	        
			my @dataTable = ();
			my @dtColumns = ({ sTitle => 'Coordinate (0-based)', sClass => 'aligncenter', sWidth => '14em'},
							 { sTitle => 'dbSNP ID', sClass => 'aligncenter'},
							 { sTitle => 'Regulome DB Score (click to see data)', sClass => 'aligncenter', sWidth => '12em'}, 
							 { sTitle => 'Other Resources', sClass => 'aligncenter', sWidth => '17em'});
			my ($n, $nsnps) = (0,0);
			my @errors = ();
			for my $c (@$input) {
				next if ( !$c || $c =~ /^#/ || $c !~ /\d+/ ); # got to have some numbers!
				$n++;
				my ( $format, $snps ) = $self->check_coord($c);
				if ( $format eq 'ERROR') {
					push @errors, { msg => $snps->[0]->[0],
									inp => $snps->[0]->[1],
									};
					next;
				}
				$nsnps += scalar( @$snps );
				for my $snp (@$snps) {
					$self->app->log->debug(
							  "Looking up $snp->[0], $snp->[1] [Detected format $format]");
				    my $res = $self->rdb->process($snp);
				    my $coordStr = $snp->[0].':'.$snp->[1];
				    my $coordRange = $snp->[0].':'.($snp->[1]-$BROWSE_PADDING).'-'.($snp->[1]+$BROWSE_PADDING);
				    $coordRange =~ s/^chr//;
				    my $snpID = $self->snpdb->getRsid($snp) || "n/a";
				    my $score = $self->rdb->score($res);
				    my @otherResources = ();
				    
				    for my $res (keys %$externalURL) {
				    	my $val = $coordRange; # default
				        $val = $snpID if $res eq 'dbSNP';
				        next if (!$val || $val eq 'n/a'); # god so hacky
				    	push @otherResources, $self->link_to($res,$externalURL->{$res}.$val);
				    }
				    
					push @dataTable, [
						$coordStr, 
						$snpID,
						($score == 5 ? "No data" : $self->link_to($score,"/snp/$snpID", 'tip' => 'Click on score to see supporting data')),
						join(' | ', @otherResources)						
					];
				}
			}
			$self->stash(snpDataTable => Mojo::JSON->new->encode({aaData => \@dataTable,
																  aoColumns => \@dtColumns,
																  bJQueryUI => 'true',
																  aaSorting => [[2,'asc'],[0,'asc']],
																  bFilter   => 0,
																  bDeferRender => 1,
																  }) );
			$self->stash( { 
				ninp  => $n,
				nsnps => $nsnps,
				error => \@errors,
			});

		}
	);
}

1;
