#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 7;
use Test::Mojo;
use lib './lib';
use_ok 'Regulome';

my $t = Test::Mojo->new('Regulome');
$t->get_ok('/welcome')->status_is(200)->content_like(qr/Mojolicious/i);
my $search = $t->get_ok('/search')->status_is(200);
my $running = $t->post_ok('/running');