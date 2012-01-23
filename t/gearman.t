use strict;
use warnings;

use Test::More 'no_plan';
use Storable qw( freeze thaw);
use List::Util qw( sum );

use_ok('Gearman::Worker');
use_ok('Gearman::Client');

die "Gearman not implemented\n";
if (my $pid = fork()) {
	print "(Parent) Do I ever get here?\n";
	my $client = Gearman::Client->new;

	$client->job_servers('127.0.0.1');
	my $result_ref = $client->do_task("sum", freeze([1,2]));
	print "1 + 2 = $$result_ref\n";

	my $tasks = $client->new_task_set;
	my $handle = $tasks->add_task(sum => freeze([ 3, 5 ]), {
		on_complete => sub { print ${ $_[0] }, "\n" }
	});
	$tasks->wait;
} else {
	print "(Child) how about here?\n";
	close STDOUT;
	my $worker = Gearman::Worker->new;
	$worker->job_servers('127.0.0.1');
	$worker->register_function(sum => sub { sum @{ thaw($_[0]->arg) } });
	$worker->work while 1;
}

