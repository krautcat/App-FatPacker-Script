package Test::App::FatPacker::Script::Core;

use strict;
use warnings;
use diagnostics;

use Cwd;
use File::Spec;

use Test::More;
use Test::Deep;
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
        scalar(@{$test_obj->{plugins}}),
        1,
        "By deault there will be one filter"
    );
    isa_ok(
        ${$test_obj->{plugins}}[0],
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

    $test_obj->{_plugin_loader}->load_plugins("App::FatPacker::Script::Filters");
    is(
        scalar(@{$test_obj->{plugins}}),
        1,
        "Number of filters must be the same"
    );
    isa_ok(
        ${$test_obj->{plugins}}[0],
        'App::FatPacker::Script::Filters',
        "Class of filter object must still the same"
    );
}

sub inc_dirs_return_value : Test(2) {
    my $test = shift;
    my $class = $test->class();
    my $test_obj = undef;

    $test_obj = $class->new(dirs => [ "t/data/lib" ],  
                            proj_dirs => [ "t/data" ],
                            script => "t/data/bin/stub.pl");
    is_deeply(
        [ 
            $test_obj->inc_dirs()
        ],
        [
            File::Spec->rel2abs("t/data/lib", cwd()),
            @INC
        ],
        "Include dirs should contain only 't/data' and INC dirs"
    );

    $test_obj = $class->new(dirs => [ "t/data/lib" ],  
                            proj_dirs => [ "t/data" ],
                            fatlib_dir => "t/data/fatlib",
                            use_cache => 1,
                            script => "t/data/bin/stub.pl");
    is_deeply(
        [
            $test_obj->inc_dirs()
        ],
        [
            File::Spec->rel2abs("t/data/lib", cwd()),
            File::Spec->rel2abs("t/data/fatlib", cwd()),
            @INC
        ],
        "Include dirs should contain fatlib directory when 'use_cache' is true"
    );
}

sub _prepare_obj {
    my $test = shift;
    my $class = $test->class();
    
    return $class->new(proj_dirs => ["t/data"],
                       fatlib_dir => "t/data/fatlib",
                       script => "t/data/bin/stub.pl",
                       modules => {
                           forced_CORE => [ "Getopt::Long" ]
                       });
}

sub test_tracing_noncore_deps : Test(1) {
    my $test = shift;
    my $test_obj = $test->_prepare_obj();
    
    $test_obj->trace_noncore_dependencies();
    cmp_deeply(
        [
            "Term::Spinner::Color",
            "Local::Test",
        ],
        set(@{$test_obj->{_non_core_deps}}),
        "Tracing should result to 2 noncore dependencies"
    );
}

sub adding_forced_deps : Test(1) {
    my $test = shift;
    my $test_obj = $test->_prepare_obj();

    $test_obj->trace_noncore_dependencies()
             ->add_forced_core_dependencies();
    cmp_deeply(
        [
            "Term::Spinner::Color",
            "Local::Test",
            "Getopt::Long"
        ],
        set(@{$test_obj->{_non_core_deps}}),
        "Tracing should result to 2 noncore dependencies"
    );    
}

1;