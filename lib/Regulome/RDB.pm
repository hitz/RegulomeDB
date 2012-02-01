package Regulome::RDB;
use Mojo::Base 'Mojolicious::Controller';
use File::Path qw/make_path remove_tree/;

our $MAX_SIZE = 1024; # maximum size for direct submit.  
# 1024 is a testing value, ca. 1Mb would be more appropriate
our $BROWSE_PADDING = 10000;
# +/- range for browse links

sub check_session {
	
	my $self = shift;
	my $session = $self->stash->{session};
	if ($session->load($session->sid)) {
		if ($session->is_expired) {
			#print STDERR "Session expired, creating a new one: ";
			$session->flush;
			$session->create;
		} else {
			#print STDERR "Old Session: ";
			if ($session->data('is_running')) {
				$session->extend_expires;
				$session->flush
			}
		}
	} else {
		#print STDERR "New Session: ";
		$session->create;
		$session->flush;
	}
	#print STDERR $self->dumper($session->sid, $session->data);	
	return $session;
}

sub submit {

	my $self = shift;
	my $data;

	my $dataTable = [];
	my $errors = [];
	my $n = 0;

	# always start a new session 
	# I think this is wrong now - because of the reload page situation
	# it needs to check the current session see if it's see running and just 
	# attach to that one.
	# should we also check the upload file name?  Does that even make sense?
	
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

			# create session, then fork
			my $size = $self->req->upload('file_data')->asset->size;
			$session->data( 
							 file_size => $size,
							 chunk => 0,
							 ninp => 0,
							 nsnps => 0,
							 estimated_time_remaining => 10*($size/$ENV{MOJO_CHUNK_SIZE}),
							 remnant => '',
			);
			
			$session->flush;
			$self->stash(session => $session); # make sure the child gets it.
			
			if (my $pid = fork()) { # not sure this is the best way to do this
				return $self->render(template => 'RDB/running'); 
			# this page will AJAX-ily check results and deliver.
			} elsif (defined $pid) {
				local $SIG{INT} = "IGNORE"; # so children die.
				$self->stash(file => $self->req->upload('file_data')->asset);
				$self->start_process;
				my $data_remains = 1;
				while($data_remains) { $data_remains = $self->continue_process }
				$self->end_process;
				exit(0);
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
	my $outfile_name =  "public/tmp/results/regulome_short.$sid.raw.json";
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
	my $data = shift || undef;
	my $errors = shift || undef;
	my $n = shift || 0;

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
	my $sid = $self->param('sid') || $self->stash->{session}->sid || 0;
	
	my $nsnps = 0;
	my $dtParams = 	{
								   aoColumns => \@dtColumns,
								   bJQueryUI => 'true',
								   aaSorting => [ [ 2, 'asc' ], [ 0, 'asc' ] ],
								   bFilter   => 0,
								   bDeferRender => 1,
								 };
	
	if ( (!$data || !$n) && $sid) {
		my $session = $self->stash->{session};
		$session->load($sid);
		my $data_file = $session->data->{outfile};
		my $error_file = $session->data->{errfile};
		$n = $session->data->{ninp};
		$nsnps = $session->data->{nsnps};
		$dtParams->{bProcessing} = 'true';
		my $ajax_url = $data_file;
		$ajax_url =~ s%.+(/tmp/.+$)%$1%;
        $dtParams->{sAjaxSource} = $ajax_url;
		
	} else {
		$nsnps = scalar @$data;
		$dtParams->{aaData}  = $data
	}
	

	$self->stash( { 
					error => $errors,
                    ninp  => $n,
					nsnps => $nsnps,
					remnant => '',
                    snpDataTable => Mojo::JSON->new->encode($dtParams),
				  } );


	$self->render(template => 'RDB/results')
}

sub start_process {
	
	my $self = shift;

	my $session = $self->stash->{session};
	
	my $outfile;
	my $sid = $session->sid;
	
	my $outfile_name = "public/tmp/results/regulome.$sid.raw.json";
	$outfile = IO::File->new("> $outfile_name") || die "Could not open $outfile_name\n";
	$outfile->print('{ "aaData": ['); # begin JSON array or arrays hack
	$session->data(outfile => $outfile_name);
	$self->stash(outfile => $outfile);
	
	
	my $errfile_name = "public/tmp/results/regulome.$sid.err";
	my $errfile = IO::File->new("> $errfile_name");
	$self->stash('errfile' => $errfile);
	$session->data(errfile => $errfile_name);			
	
		
	$session->data(is_running => '1');
	
	$session->flush; # hmmm... in case someone tries again while it's running.
	
	$errfile->print("DEBUG: Set up process for $outfile_name\n");
	$errfile->print("DEBUG: session $sid", $self->dumper($session->data));
	$errfile->flush();
}

sub continue_process {
	
	my $self = shift;
	my $session = $self->check_session;
	my $sid = $session->sid;

	my $file = $self->stash('file');
	my $outfile = $self->stash('outfile');
	my $errfile = $self->stash('errfile');
	
	my $chunks = $session->data('chunk');
	my $size = $session->data('file_size');
	my $nsnps = $session->data('nsnps');
	my $n = $session->data('ninp');
	my $remnant = $session->data('remnant') || '';
	
	my $loc = $chunks*$ENV{MOJO_CHUNK_SIZE};
	$outfile->print(",\n") if $chunks > 0; # string together output arrays.
	my $data_remains = 1;
	if ($loc >= $size ) {
		$data_remains = 0;
		$loc = $size;
	}

	$errfile->print("DEBUG: session $sid", $self->dumper($session->data));
	$errfile->print("DEBUG: Processing data (Chunk: $chunks) from user uploaded file @ $loc\n");
	$errfile->print("DEBUG: ",$size-$loc, " Data remains\n") if $data_remains;
	
	my $data = $file->get_chunk($loc);
	
	my $input = [ split( "\n", $data ) ];
	$input->[0] = ($input->[0] ? $remnant.$input->[0] : $remnant);
	$remnant = pop @$input;
	$n += scalar @$input;

	my ($res, $err)  = $self->process_chunk($input);
	
	$nsnps += scalar @$res;	    
	
	if (@$err) {
		my $err_json = $self->render(json => { error => $err }, partial => 1);
		$errfile->print($err_json."\n");
	}
		
	my $json = $self->render(json => $res, partial => 1);
	$outfile->print($self->trim_json($json));

	my $timeleft = 10*(($size/$ENV{MOJO_CHUNK_SIZE})-$chunks);
	$timeleft = "<1.0" if $timeleft < 1.0;
	$session->data(
		 	       chunk => ++$chunks,
			       ninp => $n,
			       nsnps => $nsnps,
			       remnant => $remnant,
			       error => $err,
		       estimated_time_remaining => $timeleft,
	);
		
	$session->flush;
	$errfile->flush;
	$outfile->flush;
	return $data_remains;
}

sub trim_json {
	
	# little snippet to allow us to string together arrays into JSON
	my $self = shift;
	my $json = shift;
	my $trimmed_json = substr($json , 1, length($json)-2 );
	$trimmed_json =~ s/,$//g; # remove any trailing ,s
	
	return $trimmed_json;
	
}
sub end_process {
	
	my $self = shift;
	my $session = $self->check_session;

	my $file = $self->stash('file');
	my $outfile = $self->stash('outfile');
	my $errfile = $self->stash('errfile');

	if (my $remnant = $session->data('remnant')){

		my $chunks = $session->data('chunk');
		my $nsnps = $session->data('nsnps');
		my $n = $session->data('ninp');
			
		my ($last, $last_err) = $self->process_chunk([$remnant]);

		$errfile->print($self->render(json => $last_err, partial =>1)."\n") if @$last_err;
		my $json = $self->render(json => $last, partial => 1);
		$outfile->print($self->trim_json($json));
		
		$session->data(
			chunk => $chunks++,
			ninp  => $n++,
			nsnps => $nsnps + scalar(@$last),
			error => $last_err,
		);
		    
	}
		
	$session->data( is_running => 0 );
	$outfile->print("]}\n");
	$outfile->close();
	$session->flush;   		 		

	my $sid = $session->sid;
	my $chunks = $session->data('chunk');
	$errfile->print("DEBUG: session $sid", $self->dumper($session->data));
	$errfile->print("DEBUG: Finished Processing data (Chunk: $chunks) from user uploaded file\n");


}

sub ajax_status {
	my $self = shift;
	
	my $session = $self->check_session; # this is where we might come back later.

	my @fields = qw/ninp nsnps error chunk estimated_time_remaining is_running/;
	my %jsonData = map { $_ => $session->data("$_") } @fields;

	$self->app->log->debug("checking ajax status: ".$self->dumper($session->sid, $session->data));
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
			my $coordRange =
			    $snp->[0] . ':'
			  . ( $snp->[1] - $BROWSE_PADDING ) . '-'
			  . ( $snp->[1] + $BROWSE_PADDING );
			$coordRange =~ s/^chr//;
			
			push @result,
			  [
				$snp->[0].':'.$snp->[1], #chromosome:position
			    $self->snpdb->getRsid($snp) || "n/a",
				$score,
				$coordRange,
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
