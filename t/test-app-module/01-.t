#!/usr/bin/env perl

use Test::More qw/no_plan/;

use App::FatPacker::Script;

my $app_obj = App::FatPacker::Script->new();
local @ARGV = qw/__FILE__ -q -q -q -v no-perl-strip/;
$app_obj->parse_options(@ARGV);
ok($app_obj->{verboseness} eq -2, "Check verbosity level");