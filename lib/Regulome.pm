package Regulome;
use Mojo::Base 'Mojolicious';
use lib 'lib';
use Regulome::RegulomeDB;
use Regulome::SnpDB;

# This method will run once at server start
sub startup {
	my $self = shift;

	my $regDB = RegulomeDB->new(
								 {
								   type  => 'multi',
								   dbdir => 'data/RegulomeDB'
								 }
	);

	my $snDB = SnpDB->new(
						   {
							 type          => 'single',
							 dbfile_all    => 'data/SnpDB/dbSNP132.db',
							 dbfile_common => 'data/SnpDB/dbSNP132common.db',
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
			my ( $chr, $min, $max );
			if ( $input =~ /([rs]s\d+)/ ) {

				# dbsnp ID, not sure if ss#### is used in our DB
				$format = 'dbSNPid';
				my $dbSNPid = $1;
				return ( $format, $self->snpdb->getSNPbyRsid($dbSNPid) );

			} elsif ( $input =~
					  /(chr|^)(\d+|[xy])(:|\s+)(\d+)(\.\.|-|\s+)(\d+)(.*)/i )
			{

				# BED chromsome(space)min(space)max
				$chr = $2;
				$min = $4;
				$max = $6-1; #EXCLUSIVE
				my $base = 0;
				$format = 'BED - 0 Based';

				# ch:nnnn..mmmm - or ch:nnnn-mmmm # 1 based input, subtract
				if ( $3 =~ /[:-_]/ || $5 =~ /\S/ ) {
					$format = 'Generic - 1 Based';
					$base   = 1;
					$min -= $base;
					$max -= $base;
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
						$format = 'VCF - 1 based';
					} elsif ( $f[4] =~ /(^\d+$)/ ) {

						# looks like GFF
						$min    = $1 - 1;
						$max    = $1 - 1 if $f[5] =~ /(^\d+$)/;
						$format = 'GFF - 1 based';
					} else {
						$self->app->log->debug("I thought this was VCF or GFF but I couldn't parse it: $input" );
					}
				} else {
					$self->app->log->debug("format: $input not recognized");
				}
			}
			$self->app->log->debug("format: $format invalid chromosome id: ($chr) [$input]")
			  unless $chr =~ /(chr|^)(\d+|[xXyY])/;
			$chr = "chr$chr" unless $chr =~ /^chr/;
			$self->app->log->debug(
						 "format: $format invalid min coordinate $min [$input]")
			  unless $min =~ /^(\d+)$/;

			if ( $min > $max ) {
				$self->app->log->debug(
									"Min cannot be greater than max! [$input]");
			} elsif ( $max > $min ) {
				$self->app->log->debug(
"WARNING: 2-bp range [$chr, $min, $max] detected, did you mean to specify only a single bp?"
				) if $max == $min+1;
				return ( $format,
						 $self->snpdb->getSNPbyRange( $chr, $min, $max ) );
			}
			return ( $format, [ ( $chr, $min, $max ) ] );

		}
	);

	# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
	$self->plugin('PODRenderer');
	$self->secret("fortnight");

	# Routes
	my $r = $self->routes;

	# Normal route to controller
	$r->route('/welcome')->to('example#welcome');

	$r->any(
		'/search' => sub {
		}
	);

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

			$data =~ s/(.+\n)(.+)$/$1/;    # trim trailing
			my $remnant = $2;                       # we will need this later
			my $input = [ split( "\n", $data ) ];
			$self->stash( coords  => $input );
			$self->stash( remnant => $remnant );

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
				next if ( $c =~ /^#/ );
				next unless $c =~ /\d+/;    # got to have some numbers!
				my ( $format, $snps ) = $self->check_coord($c);
				my $n = @$snps;
				$self->app->log->debug("Found $n SNPS");
				for my $snp (@$snps) {
					my ( $chr, $pos ) = $snp->[ 0 .. 1 ];
					$self->app->log->debug(
							  "Looking up $chr,$pos [Detected format $format]");
				    my $res = $self->rdb->process( $chr, $pos );
					push @res, {
						snpid   => $self->snpdb->getRsid($chr,$pos),
						score   => $self->rdb->score($res),
						results => [ map $_->[0], @$res ],
						refs    => [ map $_->[1], @$res ]
					}
				}
			}
			$self->stash( result => \@res );

		}
	);
}

1;
