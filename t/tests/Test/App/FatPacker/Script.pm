package Test::App::FatPacker::Script;

use strict;
use warnings;
use diagnostics;

use Test::More;
use base 'Test::Class';

sub class {
    'App::FatPacker::Script';
}

sub startup : Tests(startup => 1) {
    my $test = shift;
    use_ok $test->class;
}

sub constructor : Tests(3) {
    my $test  = shift;
    my $class = $test->class;
    can_ok $class, 'new';
    
    my $app_obj;
    local @ARGV;

    ok($app_obj = App::FatPacker::Script->new(),
        "... and the constructor should succeed");
    isa_ok($app_obj, 'App::FatPacker::Script');
}

1;