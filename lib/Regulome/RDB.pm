package Regulome::RDB;
use Mojo::Base 'Mojolicious::Controller';
use File::Path qw/make_path remove_tree/;

our $MAX_SIZE = 1024; # maximum size for direct submit.  
# 1024 is a testing value, ca. 1Mb would be more appropriate

sub submit_old {

	my $self = shift;
	my $data;

	my $t0 = Benchmark->new();
	if ( $data = $self->param('data') ) {
		$self->app->log->debug('Processing manual data...');
	} elsif ( $data = $self->req->upload('file_data')->asset->slurp() ) {

		# this needs to be changed for "real" 3M SNP files
		$self->app->log->debug("Processing data from file...");
	}

	$data =~ s/(.+\n)([^\n]*)$/$1/;    # trim trailing
	my $remnant = $2;                                 # we will need this later
	my $input = [ split( "\n", $data ), $remnant ];   # just process it for now.
	     #$self->stash( coords  => $input );
	$self->stash( remnant => '' );

	# below should go in some helper module or DB somewhere.
	my $BROWSE_PADDING = 10000;
	my $externalURL = {
		ENSEMBL => 'http://uswest.ensembl.org/Homo_sapiens/Location/View?r=',
		# must append X:50020991-50040991
		dbSNP => 'http://www.ncbi.nlm.nih.gov/projects/SNP/snp_ref.cgi?rs=',
		# must append DBSNP id
		UCSC => 'http://genome.ucsc.edu/cgi-bin/hgTracks?org=Human&db=hg19&position=chr',
		# must append X:50020991-50040991
	};

	my @dataTable = ();
	my @dtColumns = (
					  {
						 sTitle => 'Coordinate (0-based)',
						 sClass => 'aligncenter',
						 sWidth => '14em'
					  },
					  { sTitle => 'dbSNP ID', sClass => 'aligncenter' },
					  {
						 sTitle => 'Regulome DB Score (click to see data)',
						 sClass => 'aligncenter',
						 sWidth => '12em'
					  },
					  {
						 sTitle => 'Other Resources',
						 sClass => 'aligncenter',
						 sWidth => '17em'
					  }
	);
	my ( $n, $nsnps ) = ( 0, 0 );
	my @errors = ();
	for my $c (@$input) {
		next
		  if ( !$c || $c =~ /^#/ || $c !~ /\d+/ );   # got to have some numbers!
		$n++;
		my ( $format, $snps ) = $self->check_coord($c);
		if ( $format eq 'ERROR' ) {
			push @errors,
			  {
				msg => $snps->[0]->[0],
				inp => $snps->[0]->[1],
			  };
			next;
		}
		$nsnps += scalar(@$snps);
		for my $snp (@$snps) {
			$self->app->log->debug(
				   "Looking up $snp->[0], $snp->[1] [Detected format $format]");
			my $res      = $self->rdb->process($snp);
			my $coordStr = $snp->[0] . ':' . $snp->[1];
			my $coordRange =
			    $snp->[0] . ':'
			  . ( $snp->[1] - $BROWSE_PADDING ) . '-'
			  . ( $snp->[1] + $BROWSE_PADDING );
			$coordRange =~ s/^chr//;
			my $snpID          = $self->snpdb->getRsid($snp) || "n/a";
			my $score          = $self->rdb->score($res);
			my @otherResources = ();

			for my $res ( keys %$externalURL ) {
				my $val = $coordRange;    # default
				$val = $snpID if $res eq 'dbSNP';
				next if ( !$val || $val eq 'n/a' );    # god so hacky
				push @otherResources,
				  $self->link_to( $res, $externalURL->{$res} . $val );
			}

			push @dataTable,
			  [
				$coordStr,
				$snpID,
				(
				   $score == 5
				   ? "No data"
				   : $self->link_to(
								$score, "/snp/$snpID",
								'tip' => 'Click on score to see supporting data'
				   )
				),
				join( ' | ', @otherResources )
			  ];
		}
	}

	$self->stash(
				  snpDataTable =>
					Mojo::JSON->new->encode(
								 {
								   aaData    => \@dataTable,
								   aoColumns => \@dtColumns,
								   bJQueryUI => 'true',
								   aaSorting => [ [ 2, 'asc' ], [ 0, 'asc' ] ],
								   bFilter   => 0,
								   bDeferRender => 1,
								 }
					)
	);
	$self->stash(
				  {
					ninp  => $n,
					nsnps => $nsnps,
					error => \@errors,
				  }
	);

	$self->render(template => 'RDB/running');

}
sub check_session {
	
	my $self = shift;
	my $session = $self->stash->{session};
	if ($session->load) {
		if ($session->is_expired) {
			$session->flush;
			$session->create;
		} else {
			if ($session->data('is_running')) {
				$session->extend_expires;
				$session->flush
			}
		}
	} else {
		$session->create;
		$session->flush;
	}	
	print STDERR $self->dumper($session->sid, $session->data);
	return $session;
}

sub submit {

	my $self = shift;
	my $data;

	my $dataTable = [];
	my $errors = [];
	my $n = 0;

	# always start a new session (although I guess we could allow people in the future to run > 1 job)
	my $session = $self->stash->{session};
	if ($session->load) {
		#delete existing session
		$session->expire unless $session->is_expired;
		$session->flush;
	}
	$session->create;
	my $sid = $session->sid;
	make_path('public/tmp/results', {mode => 0777}) unless -d 'public/tmp/results';
	
	if ( $self->req->upload('file_data') ) {

		if ($self->req->upload('file_data')->asset->size() > $MAX_SIZE) {
			
			# set sessions and temp files
			if (my $pid = fork()) { # not sure this is the best way to do this
			    my $size = $self->req->upload('file_data')->asset->size;
				$session->data( 
							 file_size => $size,
							 chunk => 0,
							 count => 0,
							 nsnps => 0,
							 estimated_time_remaining => 10*($size/$ENV{MOJO_CHUNK_SIZE}),
							 remnant => '',
				);
			
				$session->flush;
				$self->render(template => 'RDB/running'); 
			# this page will AJAX-ily check results and deliver.
			} elsif (defined $pid) {
				$self->stash(file => $self->req->upload('file_data')->asset);
				close STDOUT;					
				$self->start_process;
				my $data_remains = 1;
				while($data_remains) { $data_remains = $self->continue_process }
				$self->end_process;
				
			} else {
				die "Could not fork $! in RDB.pm!";
			}
			
		} else {
			$data = $self->req->upload('file_data')->asset->slurp();
			$self->app->log->debug("Processing whole file...");
		}
		
	} elsif ( $data = $self->param('data') ) {
		$self->app->log->debug('Processing manual data...');
		
	}
	
	my $input = [ split( "\n", $data ) ];
	$n = scalar @$input;
	my ($res, $err) = $self->process_chunk($input);
	push @$dataTable, @$res;
	push @$errors, @$err if @$err;
	
	make_path('public/tmp/results') unless -d 'public/tmp/results';
	my $outfile_name =  "public/tmp/results/regulome.$sid.raw.json";
	my $outfile = IO::File->new("> $outfile_name") || die "Could not open $outfile_name!";
	$session->data(outfile=>$outfile_name);

	my $json = $self->render(json => $dataTable, partial => 1); # partial will not detach
	$outfile->print($json);
	
	$session->flush;
	$self->display($dataTable, $errors, $n);		
	# should this be in template?
}

sub display {
	
	my $self = shift;
	my $data = shift;
	my $errors = shift;
	my $n = shift;
	
	my @dtColumns = (
					  {
						 sTitle => 'chromosome',
						 sClass => 'aligncenter',
						 sWidth => '2em'
					  },
					  {
						 sTitle => 'Coordinate (0-based)',
						 sClass => 'aligncenter',
						 sWidth => '12em'
					  },
					  {
						 sTitle => 'Regulome DB Score (click to see data)',
						 sClass => 'aligncenter',
						 sWidth => '12em'
					  },
	);

	$self->stash( { 
					error => $errors,
                    ninp  => $n,
					nsnps => scalar(@$data),
					remnant => '',
                    snpDataTable =>
				 		 Mojo::JSON->new->encode(
								 {
								   aaData    => $data,
								   aoColumns => \@dtColumns,
								   bJQueryUI => 'true',
								   aaSorting => [ [ 2, 'asc' ], [ 0, 'asc' ] ],
								   bFilter   => 0,
								   bDeferRender => 1,
								 }
						)
				  } );


	$self->render(template => 'RDB/results')
}

sub start_process {
	
	my $self = shift;

	my $session = $self->check_session;
	
	my $outfile;
	my $outfile_name = $session->data('outfile') || '';  # this probably shouldn't be set.
	my $sid = $session->sid;
	unless ($outfile_name) {
		$outfile_name = "public/tmp/results/regulome.$sid.raw.json";
		$outfile = IO::File->new("> $outfile_name") || die "Could not open $outfile_name\n";
		$outfile->print('['); # begin JSON array or arrays hack
		$session->data(outfile => $outfile_name);
	}
		
	$session->data(is_running => '1');
	
	$session->flush; # hmmm... in case someone tries again while it's running.
	
	$self->stash(outfile => $outfile);

}
sub continue_process {
	
	my $self = shift;
	my $session = $self->check_session;

	my $file = $self->stash('file');
	my $outfile = $self->stash('outfile');
	
	my $chunks = $session->data('chunk');
	my $size = $session->data('file_size');
	my $nsnps = $session->data('nsnps');
	my $n = $session->data('ninp');
	my $remnant = $session->data('remnant');
	
	
	my $loc = $chunks*$ENV{MOJO_CHUNK_SIZE};
	
	my $data_remains = 1;
	if ($loc >= $size ) {
		$data_remains = 0;
		$loc = $size;
	}

	$self->app->log->debug("Processing data (Chunk: $chunks) from file: ${file->path} @ $loc");
	my $data = $file->get_chunk($loc);
	
	my $input = [ split( "\n", $data ) ];
	$input->[0] = $remnant.$input->[0];
	$remnant = pop @$input;
	$n += scalar @$input;
	my ($res, $err)  = $self->process_chunk($input);
	
	$nsnps += scalar @$res;	    
	#push @$errors, @$err if @$err;  Keep errors "local" - or should we dump to file??
	my $json = $self->render(json => $res, partial => 1);
	$outfile->print($json);

	$session->data(
		 	       chunk => $chunks++,
			       ninp => $n,
			       nsnps => $nsnps,
			       remant => $remnant,
			       error => $err,
				   estimated_time_remaining => 10*(($size/$ENV{MOJO_CHUNK_SIZE})-$chunks),
	);
		
	$session->flush;
	return $data_remains;
}

sub end_process {
	
	my $self = shift;
	my $session = $self->check_session;

	my $file = $self->stash('file');

	if (my $remnant = $session->data('remnant')){

		my $chunks = $session->data('chunk');
		my $nsnps = $session->data('nsnps');
		my $n = $session->data('ninp');
			
		my ($last, $last_err) = $self->process_chunk([$remnant]);

		$self->stash(error => $last_err);
		$file->print($self->render(json => $last, partial => 1));
		
		$session->data(
			chunk => $chunks++,
			ninp  => $n++,
			nsnps => $nsnps + scalar(@$last),
			error => $last_err,
		);
		    
	}
		
	$session->data( is_running => 0 );
	$file->print("]");
	$file->close();
	$session->flush;   		 		

}

sub ajax_status {
	my $self = shift;
	
	my $session = $self->check_session;

	my @fields = qw/ninp nsnps error chunk estimated_time_remaining is_running/;
	
	my %jsonData = map { $_ => $session->data("$_") } @fields;

	print STDERR "checking ajax status: ", $self->dumper($session->sid, $session->data);
	$self->render(json => \%jsonData);
	
}

sub process_chunk {

    my $self = shift;
	my $chunk = shift;

	my @result = ();
	my @errors = ();

	for my $c (@$chunk) {
		next
		  if ( !$c || $c =~ /^#/ || $c !~ /\d+/ );   # got to have some numbers!
		my ( $format, $snps ) = $self->check_coord($c);
		if ( $format eq 'ERROR' ) {
			push @errors,
			  {
				msg => $snps->[0]->[0],
				inp => $snps->[0]->[1],
			  };
			next;
		}

		for my $snp (@$snps) {
			my $res      = $self->rdb->process($snp);
			my $score          = $self->rdb->score($res);
			push @result,
			  [
				$snp->[0], #chromosome
			        $snp->[1], #position
				$score
			  ];
		}
	}
	return \@result, \@errors;
	  
}

sub check_coord {

	my $self  = shift;
	my $input = shift;
	chomp($input);    ## shouldn't have any trailing \n but just in case
	$input =~ s/^\s+//;

	# try to guess the format

	my $format = "Unknown";
	my ( $chr, $min, $max ) = ( 'None', -1, -1 );
	# might be faster to split then match.
	if ( $input =~ /^\s*([rs]s\d+)\s*$/ ) {

		# note that "big formats" might also have rs# in them!
		# dbsnp ID, not sure if ss#### is used in our DB
		$format = 'dbSNPid';
		my $dbSNPid = $1;
		return ( $format, [ $self->snpdb->getSNPbyRsid($dbSNPid) ] );

	} elsif ( $input =~ /(chr|^)(\d+|[xy])(:|\s+)(\d+)(\.\.|-|\s+)(\d+)(.*)/i )
	{

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
			$max--;    #EXCLUSIVE
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
				return (
					'ERROR',
					[
					    ["I thought this was VCF or GFF but I couldn't parse it:",$input ]
					]
				);
			}
		} else {
			return ( "ERROR", [ [ "Input not recognized", $input ] ] );
		}
	}
	return ( "ERROR",
			 [ [ "format: $format invalid chromosome id: ($chr)", $input ] ] )
	  unless $chr =~ /(chr|^)(\d+|[xy])/i;
	  
	$chr = "chr$chr" unless $chr =~ /^chr/;
	$chr =~ s/([xy])/\u$1/;
	
	return ( "ERROR",
			 [ [ "format: $format invalid min coordinate $min", $input ] ] )
	  unless $min =~ /^(\d+)$/;

	if ( $min > $max ) {
		return (
				 "ERROR",
				 [
				   [
					 "Min ($min) cannot be greater than max ($max) in range!",
					 $input
				   ]
				 ]
		);
	} elsif ( $max > $min ) {

		$self->app->log->debug("WARNING: 2-bp range [$chr, $min, $max] detected, did you mean to specify only a single bp?") if ( $max == $min + 1 );
		return ( $format,
				 $self->snpdb->getSNPbyRange( [ $chr, $min, $max + 1 ] ) );

		# 1 is added back because the SNPS are stored as 1-base intervals.
	}
	return ( $format, [ [ $chr, $min ] ] );

}
1;
