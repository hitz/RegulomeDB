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
	
	$r->any('/snp/:id/')->to(controller => 'SNP', action => 'id');
	$r->any('/snp/:chr/:nt')->to(controller => 'SNP', action => 'coord');


	$r->get( 
	    '/running' => sub { shift->render({template => 'search'})
	    });
	    
	$r->post('/running')->to(controller => 'RDB', action => 'submit');
}

1;
