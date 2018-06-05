#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw/GetOptions/;

use Term::Spinner::Color;

use Local::Test;


GetOptions
    "foo!"  => \(my $foo = 0),
    "bar=s" => \(my $bar);

my $spinner = Term::Spinner::Color->new();

$spinner->start();
foreach my $step (Local::Test::steps()) {
    sleep 1;
    $spinner->next();
}
sleep 1;
$spinner->done();