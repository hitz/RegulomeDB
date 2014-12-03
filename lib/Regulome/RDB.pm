package Regulome::RDB;
use Mojo::Base 'Mojolicious::Controller';
use File::Path qw/make_path remove_tree/;

our $MAX_SIZE = 24; # maximum size for direct submit.  
our $MAX_ERRORS = 1000; # maximum number of errors before quit.
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
	    my $size = $self->req->upload('file_data')->asset->size;
	    #print STDERR "File uploaded size: $size\n";

		if ($size > $MAX_SIZE) {

			# create session, then fork
			$session->data( 
							 file_size => $size,
							 chunk => 0,
							 ninp => 0,
							 nsnps => 0,
							 estimated_time_remaining => 1.0*($size/$ENV{MOJO_CHUNK_SIZE}),
							 remnant => '',
							 error => [],
			);
			
			$session->flush;
			$self->stash(session => $session); # make sure the child gets it.
			
			if (my $pid = fork()) { # not sure this is the best way to do this
			    #print STDERR "forking child\n";
			    return $self->render(template => 'RDB/running'); 
			# this page will AJAX-ily check results and deliver.
			} elsif (defined $pid) {
				local $SIG{INT} = "IGNORE"; # so children die.
				$self->stash(file => $self->req->upload('file_data')->asset);
				$self->start_process;
				my $data_remains = 1;
				while($data_remains) { $data_remains = $self->continue_process }
				$self->end_process;
				#print STDERR "killing child\n";
				exit(0);
			} else {
				die "Could not fork $! in RDB.pm!";
			}
			
		} else {
		    #print STDERR "File very small so just processing in-line\n";
			$data = $self->req->upload('file_data')->asset->slurp();
			$self->app->log->debug("Processing whole file...");
		}
		
	} elsif ( $data = $self->param('data') ) {
	        #print STDERR "Just a regular submit\n";
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

	my $json = $self->render(json => {aaData => $dataTable}, partial => 1); # partial will not detach
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
						 sTitle => '<a title="help on scoring" href="/help#score"><span class="text-ui-icon ui-icon ui-icon-help"></span></a>Regulome DB Score',
						 sClass => 'aligncenter',
						 sWidth => '14em'
					  },
					  {
						 sTitle => 'Other Resources',
						 sClass => 'aligncenter',
						 sWidth => '18em'
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
        $errors = $session->data->{error};
		
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
	my $all_errors = $session->data('error') || [];
	my $remnant = $session->data('remnant') || '';
	
	my $loc = $chunks*$ENV{MOJO_CHUNK_SIZE};
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
		push @$all_errors, @$err;
		#print STDERR "found ", scalar @$err, " new errors, total now: ",scalar @$all_errors,"\n";
		my $err_json = $self->render(json => { error => $err }, partial => 1);
		$errfile->print($err_json."\n");
	}
	
	if(@$res) {
#		$outfile->print(",\n") if $chunks > 0; # string together output arrays.
		$outfile->print(",") if $chunks > 0; # string together output arrays.
	    my $json = $self->render(json => $res, partial => 1);
	    $outfile->print($self->trim_json($json));
	}

	my $timeleft = 10*(($size/$ENV{MOJO_CHUNK_SIZE})-$chunks);
	$timeleft = "<1.0" if $timeleft < 1.0;
	if(@$all_errors > $MAX_ERRORS) {
		my $msg = "Greater than $MAX_ERRORS erros, giving up after $n lines";
		warn $msg;
		errfile->print($msg);
		unshift @$all_errors, { inp => "GLOBAL ERROR", msg => $msg};
		
	}
	$session->data(
		 	       chunk => ++$chunks,
			       ninp => $n,
			       nsnps => $nsnps,
			       remnant => $remnant,
			       error => $all_errors,
		       	   estimated_time_remaining => $timeleft,
	);
		
	$session->flush;
	$errfile->flush;
	$outfile->flush;
	
	return (@$all_errors > $MAX_ERRORS ? 0 : $data_remains);
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
		my $all_errors = $session->data('error') || [];
			
		my ($last, $last_err) = $self->process_chunk([$remnant]);

		if(@$last_err) {
			push @$all_errors, @$last_err;
			$errfile->print($self->render(json => $last_err, partial =>1)."\n");
		}
		if (@$last) {
		    my $json = $self->render(json => $last, partial => 1);
		    $outfile->print(",".$self->trim_json($json));
		}

		$session->data(
			chunk => $chunks++,
			ninp  => ++$n,
			nsnps => $nsnps + scalar(@$last),
			error => $all_errors,
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
			my $score          = $self->rdb->score($res,$snp->[0]);
			my $coordRange =
			    $snp->[0] . ':'
			  . ( $snp->[1] - $BROWSE_PADDING ) . '-'
			  . ( $snp->[1] + $BROWSE_PADDING );
			$coordRange =~ s/^chr//;
			
			push @result,
			  [
				$snp->[0].':'.$snp->[1], #chromosome:position
			    $self->snpdb->getRsid($snp) || "n/a",
				$score->{score},
				$coordRange,
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

	} elsif ( $input =~ /(chr|^)(\d+|[xy])(:|\s+)([,0-9]+)(\.\.|-|\s+)([,0-9]+)(.*)/i )
	{

		# BED chromsome(space)min(space)max
		$chr = $2;
		$min = $4;
		$max = $6;
		$min =~ s/,//g;
		$max =~ s/,//g;

		#Dropping 1 based raw input support (VCF and GFF are still 1 based) - APB
		# ch:nnnn..mmmm - or ch:nnnn-mmmm # 1 based input, subtract
		if ( $3 =~ /[:-_]/ || $5 =~ /\S/ ) {
			$format = 'Generic - 0 Based';
			#$min--;
			if($max != $min) {
				$max--;	#EXCLUSIVE
			}
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

sub download {

    my $self=shift;
    my $format = $self->param('format') || 'bed'; ## default dl format is BED
    my $sid = $self->param('sid') || $self->render(template => 'RDB/dl_error');

    my $resultsDir = 'public/tmp/results';
    my $fn = "regulome.$sid.raw.json";

    $fn = "regulome_short.$sid.raw.json" unless (-e "$resultsDir/$fn");

    open(FH, "$resultsDir/$fn")  || die "Could not find output for session $sid ($fn)!";
    # turn the the below two lines on to get "autodownload" - perhaps should set up a flag.
    $self->app->types->type(txt => 'application/octet-stream');
    #$self->tx->req->headers->header('content-disposition' => "attachment; filename=regulomedb_results.$format");
    $self->tx->res->headers->content_disposition("attachment; filename=regulomedb_results.$format");
    my $results = <FH>;

    my $table = Mojo::JSON->new->decode($results);

    my $snps = [];
    # performance note: downloading very large results (millions) takes time and maybe shoudl be optimized

    $snps = ( $self->param('nosort') ?  $table->{'aaData'} : [ sort { $a->[2] cmp $b->[2] } @{$table->{'aaData'}} ] );

    my @out = ();

    for (@$snps) {
	$_->[0] =~/(chr.*):([0-9]+)/;
	my $ch = $1;
	my $st = $2;
	if ($format eq 'bed') {
	    my $intScore = $_->[2];
	    $intScore =~ s/[^0-9]//g;

            #  seqid start end name score strand (grapics) # comment
	    push @out, join("\t", 
#	       ($ch,$st,$st+1,'SNP',$intScore,0,'.','.','.',"# rsid: $_->[1]; score: $_->[2]") );
	       ($ch,$st,$st+1,"$_->[1];$_->[2]") );

	} elsif ($format eq 'gff') {
	    my $id = "ExtendedScore=$_->[2]";
	    $id .= ";Rsid=$_->[1]" unless $_->[1] eq 'n/a';
            # seqid source feature_type start end  score strand phase attributes(key=value;) -- coords in 1-base
	    my $floatScore = $_->[2];
	    $floatScore =~ s/[^0-9]//g;
	    $floatScore = sprintf('%2.1f', $floatScore);
	    push @out, join( "\t", 
              ($ch, "RegulomeDB","snp",$st+1,$st+1,$floatScore,'.','.',$id) );

	} elsif ($format eq 'full') {
	    my $format_template = {
		'Single_Nucleotides' => { 'Method' => 1,
					  			'Affected Gene' => 1,
									'Cell Type' => 1,},
		'Motifs'	=> { 'Method' => 1,
					  			'Motif' => 1, 
									'Cell Type' => 1,},
		'Chromatin_Structure' => { 'Method' => 1,
							'Cell Type' => 1,
							'Additional Info' => 1,},
		'Protein_Binding'     => { 'Method' => 1,
							'Bound Protein' => 1,
							'Cell Type' => 1,
							'Additional Info' => 1,},
		'Related_Data'        => { 'Method' => 1,
					   'Annotation' => 1,
						'Cell Type' => 1,},
	    };
	    my $res = $_->[4];
	    @out  = ( join("\t",qw/#chromosome coordinate rsid hits score/) ) unless @out;
	    my $dat = '';
	    if ($_->[2] ne 7) { 
		
		for my $class (keys %$format_template) {
		    my %outData = ();
		    for my $hit (@{ $res->{$class}->{hits} } ) {
			
			$outData{ join( '|',($class, @$hit{keys %{ $format_template->{$class} }}) ) }++
		    }
		    $dat .= ', ' if ($dat && keys %outData);
		    $dat .= join(', ', keys %outData);
			
		}

	    } else {

		$dat = "No data";

	    }
	    # possibly explicitly adding \t and \n is faster
	    push @out, join("\t", ($ch, $st, $_->[1], $dat, $_->[2]) );
	    
	} else {
	    push @out, "Undefined Format: $format";
	    last;
	}

    }
    $self->cookie(fileDownloadToken => $self->param('download_token_value_id'));
    $self->render(text => join("\n", @out), format => 'txt');
    

}
1;
