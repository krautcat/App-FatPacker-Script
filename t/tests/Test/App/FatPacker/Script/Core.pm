package Test::App::FatPacker::Script::Core;

use strict;
use warnings;
use diagnostics;

use Test::More;
use base 'Test::Class';

use App::FatPacker::Script::Core;

sub class {
    'App::FatPacker::Script::Core';
}

sub has_default_filter : Tests(3) {
    my $test = shift;
    my $class = $test->class();
    my $test_obj = $class->new(script => "t/data/bin/stub.pl");
    
    is(
        scalar(@{$test_obj->{_filters}}),
        1,
        "By deault there will be one filter"
    );
    isa_ok(
        ${$test_obj->{_filters}}[0],
        'App::FatPacker::Script::Filters',
        "Core object must contain one filter object"
    );
    ok(
        $test_obj->can('filter_noncore_dependencies'),
        "Dispatch to missing filter_* methods should be successful"
    );
}

sub add_existing_filter : Tests(2) {
    my $test = shift;
    my $class = $test->class();
    my $test_obj = $class->new(script => "t/data/bin/stub.pl");

    $test_obj->load_filters("App::FatPacker::Script::Filters");
    is(
        scalar(@{$test_obj->{_filters}}),
        1,
        "Number of filters must be the same"
    );
    isa_ok(
        ${$test_obj->{_filters}}[0],
        'App::FatPacker::Script::Filters',
        "Class of filter object must still the same"
    );
}

sub inc_dirs_return_value : Test(1) {
    
}

1;