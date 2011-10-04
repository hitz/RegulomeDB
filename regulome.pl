#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojolicious::Plugin::Database;
use lib 'lib';
use RegulomeDB; # temporary workaround
use SnpDB;

#$ENV{MOJO_MAX_MESSAGE_SIZE} = 5000000000; # 5 GB upload limit
$ENV{MOJO_CHUNK_SIZE} = 131072; # 128K ~1000 VCF lines
# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
plugin 'PODRenderer';
app->secret("fortnight");
my $DBDIR = 'RegulomeDB/RDB'; #should be in config

my $regDB = RegulomeDB->new({type => 'multi',
							dbdir => $DBDIR});

my $snDB = SnpDB->new({type => 'single',
					   dbfile_all => 'SnpDB/dbSNP132.db',
					   dbfile_common => 'SnpDB/dbSNP132common.db',
						});
						
helper rdb => sub { return $regDB };
helper snpdb => sub { return $snDB };

sub startup {
        my $self = shift;
	   
	   # ONLY in full Mojolicious app
        $self->plugin('database', { 
            dsn      => 'dbi:SQLite:dbname=$singleDBfile',
            username => '',
            password => '',
            options  => { RaiseError => 1, AutoCommit => 0 },
            helper   => 'rdb',
            });
}

## routing
get '/welcome' => sub {
  my $self = shift;
  $self->render('index');
};

any '/search' => sub {

};

post '/running' => sub {
 
  my $self = shift;
  
  my $data;
  if($data = $self->param('data') ) {
  	  $self->app->log->debug('Processing manual data...');
  } elsif (  $data = $self->req->upload('file_data')->asset->get_chunk()){
  	  # this needs to be changed for "real" 3M SNP files
  	  $self->app->log->debug("Processing data from file...");
  }

  $data =~ s/(.+\n)(.+)$/$1/; # trim trailing
  my $remnant = $2;  # we will need this later
  my $input = [ split("\n", $data) ];
  $self->stash(coords => $input);
  $self->stash(remnant => $remnant);
  ## for each line input
   ## skip comments (/^#)
   ## detect format
     # ".."  (chr)c# min..max
     # VCF (chr)c# min dbSNPid [crap]
     # GFF (chr)c# (source) (featureType) min max [ crap ]
     # rs[0-9]+
     ## LOOKUP in DBSNP to get coordinate
     ## store previous input data somewhere
   my @res = ();
   for my $c (@$input) {
   	  	next if($c =~ /^#/);
   	  	next unless $c =~ /\d+/; # got to have some numbers!
   	  	my ($format, $snps) = $self->check_coord($c);
   	  	my $n = @$snps;
   	  	$self->app->log->debug("Found $n SNPS");
   	  	for my $snp (@$snps) {
   	  		my ($chr, $pos) = $snp->[0..1];
	 		$self->app->log->debug("Looking up $chr,$pos [Detected format $format]");
    		push @res, ($chr, $pos, $self->rdb->score( [ $self->rdb->process($chr, $pos) ]));
   	  	}
    }
    $self->stash(result => \@res);
    
};
helper check_coord => sub {
	
	my $self = shift;
	my $input = shift;
	chomp($input); ## shouldn't have any trailing \n but just in case
	$input =~ s/^\s+//;
	# try to guess the format
	
	my $format = "Unknown";
	my ($chr, $min, $max);
	if ($input =~ /([rs]s\d+)/) {
		# dbsnp ID, not sure if ss#### is used in our DB
		$format = 'dbSNPid';
		my $dbSNPid = $1;
		return ($format, $self->snpdb->getSNPbyRsid($dbSNPid) );
		
	} elsif ($input =~ /(chr|^)(\d+|[xy])(:|\s+)(\d+)(\.\.|-|\s+)(\d+)(.*)/i) {
		# BED chromsome(space)min(space)max
		$chr = $2; 	
		$min = $4;
		$max = $6;
		my $base = 0;
		$format = 'BED - 0 Based';
		# ch:nnnn..mmmm - or ch:nnnn-mmmm # 1 based input, subtract		
		if ($3 =~ /[:-_]/ || $5 =~ /\S/) {
			$format = 'Generic - 1 Based';
			$base =1;
			$min -= $base;
			$max -= $base;
		}
	} else {
		my @f = split('\s+',$input);
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
				$self->app->log->debug("I thought this was VCF or GFF but I couldn't parse it: $input");
			}
		} else {
			$self->app->log->debug("format: $input not recognized");
		}
	}
	$self->app->log->debug("format: $format invalid chromosome id: ($chr) [$input]") unless $chr =~ /(chr|^)(\d+|[xXyY])/;
	$chr = "chr$chr" unless $chr =~ /^chr/;
	$self->app->log->debug("format: $format invalid min coordinate $min [$input]") unless $min =~ /^(\d+)$/;
	
	if ($min > $max) {
		$self->app->log->debug("Min cannot be greater than max! [$input]");
	} elsif ($max > $min) {
		$self->app->log->debug("WARNING: 2-bp range [$chr, $min, $max] detected, did you mean to specify only a single bp?");
		return ($format, $self->snpdb->getSNPbyRange($chr, $min, $max));
	}
	return ($format, [($chr, $min, $max)]);
	
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to Mojolicious!

@@ search.html.ep
% layout 'default';
% title 'Search ReguomeDB';
<div id='search'>
   <div id='manual_input'>
       % my @attrs = (method => 'POST', enctype => 'multipart/form-data');
       %= form_for running => @attrs => begin
           %= text_area 'data', rows => '40', style =>"width: 400px;" => begin
11 5248490	5248491
4:33493..132333
chr6    138043309 138047320
7 88888 99999
chr4 222 666
 x:55041617-55041641
           % end
          %= submit_button 'Submit'
       % end    
   </div>
   </div>
   <div id='upload'>
       %= form_for running => @attrs => begin
          %= file_field 'file_data'
          %= submit_button 'Upload'
       % end
   </div>
</div>
@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>

@@ running.html.ep
% layout 'default';
% title 'Running ReguomeDB search...';
<div id='input'>
   <h1>Input Data</h1>
  <pre>
   % for (my $i=0; $i<@$coords;$i++) {
    %= "$i $coords->[$i]"
    % }
  </pre>
  <pre>Left over:<%= $remnant %></pre>
</div>
<div id='output'>
  <h1>Results</h1>
  <pre>
   %= dumper $result
  </pre>
<div>