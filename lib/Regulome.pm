package Regulome;
use Mojo::Base 'Mojolicious';
use lib 'lib';
use Regulome::RegulomeDB;
use Regulome::SnpDB;
use MojoX::Session::Store::File;

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
	#$self->plugin('RequestTimer');
	$self->plugin(
			session => {
				stash_key => 'session',
				store     => 'file' , #MojoX::Session::Store::File->new(), # could also be DBI or Libmemcached
				expires_delta => 3600, # 1 hour, can be extended
			});
	

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
	    
	$r->post('/results')->to(controller => 'RDB', action => 'submit'); # post without chunking

	$r->post('/running')->to(controller => 'RDB', action => 'submit'); # post with chunking

	$r->get('/status')->to(controller => 'RDB', action => 'ajax_status');
	
	$r->get('/results')->to(controller => 'RDB', action => 'results'); # currently undefined

	$r->get('/results/:sid/')->to(controller => 'RDB', action => 'display'); # get stored results
	
	$r->get('/rsid/:chr/:nt')->to(controller => 'SNP', action => 'ajax_rsid');

	$r->get('/rsid/:id')->to(controller => 'SNP', action => 'ajax_coord');
	
}

1;
