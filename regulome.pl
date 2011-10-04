#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojolicious::Plugin::Database;
use lib 'lib';
use RegulomeDB; # temporary workaround

#$ENV{MOJO_MAX_MESSAGE_SIZE} = 5000000000; # 5 GB upload limit
$ENV{MOJO_CHUNK_SIZE} = 131072; # 128K ~1000 VCF lines
# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
plugin 'PODRenderer';
app->secret("fortnight");
my $DBDIR = 'RegulomeDB/RDB'; #should be in config

my $regDB = RegulomeDB->new({type => 'multi',
							dbdir => $DBDIR});

helper rdb => sub {return $regDB};

sub startup {
        my $self = shift;
	   
	   # does nothing?
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
   	  	my ($format, $chr, $min, $max) = $self->rdb->check_coord($c);
 		$self->app->log->debug("Looking up $chr: $min, $max [Detected format $format]");
    	push @res, ($chr, $min, $max, $self->rdb->score( [ $self->rdb->process($chr, $min, $max) ]));
    }
    $self->stash(result => \@res);
    
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