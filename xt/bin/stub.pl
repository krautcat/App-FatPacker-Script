#!/usr/bin/env perl

use strict;
use warnings;

use Local::Test;
use Term::Spinner::Color;

my $spinner = Term::Spinner::Color->new();

$spinner->start();
foreach my $step (Local::Test::steps()) {
    sleep 1;
    $spinner->next();
}
sleep 1;
$spinner->done();