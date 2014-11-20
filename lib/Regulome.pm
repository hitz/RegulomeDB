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
	my $regDB;
	my $snDB;
	# eval added when DB not available 
	eval {
	  $regDB = Regulome::RegulomeDB->new(
								 {
								   type  => 'multi',
								   dbdir => 'data/RegulomeDB'
								 }
	  );

	  $snDB = Regulome::SnpDB->new(
						   {
							 type          => 'single',
							 dbfile_all    => 'data/SnpDB/dbSNP141.db',
							 dbfile_common => 'data/SnpDB/dbSNP141Common.db',
						   }
	  );

	};
	$self->helper( 'rdb'   => sub { return $regDB } );
	$self->helper( 'snpdb' => sub { return $snDB } );

	# Documentation browser under "/perldoc" (this plugin requires Perl 5.10)
	$self->plugin('PODRenderer');
	$self->secrets(['fortnight']);
	#$self->plugin('RequestTimer');
	$self->plugin(
			session => {
				stash_key => 'session',
				store     => 'file' , #MojoX::Session::Store::File->new(), # could also be DBI or Libmemcached
				expires_delta => 3600, # 1 hour, can be extended
			});
	

	# config
	my $config = $self->plugin('Config');
	$self->mode('development'); ## writes log file

	# Routes
	my $r = $self->routes;

	# Normal route to controller
	$r->route('/welcome')->to('example#welcome');

	$r->any( '/search' => sub {} );
	$r->any( '/about' => sub {} );
	$r->any( '/help' => sub {} );
	$r->any( '/downloads' => sub { shift->render(template => 'download') } );
	$r->any( '/GWAS/' => sub { shift->render_static('/GWAS/index.html') } );

	$r->any( '/' => sub { shift->render(template => 'search') } );
	$r->any( '/index' => sub { shift->render(template => 'search') } );
	
	$r->any('/snp/:id/')->to(controller => 'SNP', action => 'id');
	$r->any('/snp/:chr/:nt')->to(controller => 'SNP', action => 'coord');


	$r->get( 
	    '/running' => sub { shift->render(template => 'search')
	    });
	    
	$r->post('/results')->to(controller => 'RDB', action => 'submit'); # post without chunking

	$r->post('/running')->to(controller => 'RDB', action => 'submit'); # post with chunking

	$r->get('/status')->to(controller => 'RDB', action => 'ajax_status');
	
	$r->get('/results')->to(controller => 'RDB', action => 'results'); # currently undefined

	$r->get('/results/:sid/')->to(controller => 'RDB', action => 'display'); # get stored results
	
	$r->get('/rsid/:chr/:nt')->to(controller => 'SNP', action => 'ajax_rsid');

	$r->get('/rsid/:id')->to(controller => 'SNP', action => 'ajax_coord');

	$r->post('/download')->to(controller => 'RDB', action => 'download');
       
	$r->get('/download/:sid/')->to(controller => 'RDB', action => 'download');
	
}

1;
