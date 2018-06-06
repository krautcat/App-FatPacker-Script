package Test::App::FatPacker::Script::Filters;

use strict;
use warnings;
use diagnostics;
use version 0.77;

use List::Util qw/uniq/; 

use Test::More;
use Test::Deep;
use base 'Test::Class';

use App::FatPacker::Script::Filters;

sub class {
    'App::FatPacker::Script::Filters';
}

sub _create_mock_object {
    my $test = shift;
    my %params = @_;
    my @keys_params = keys %params;

    my $mock_class = "Mock::App::FatPacker::Script::Core";
    {
        no strict 'refs'; # no_critic
        *{ "${mock_class}::inc_dirs" } = sub {
            my $self = shift;
            my %params = @_;
            $params{proj_dir} = exists $params{proj_dir} ? $params{proj_dir} : 1;

            return uniq (
                ( $params{proj_dir} ? @{$self->{proj_dir}} : () ),
                ( $self->{use_cache} ? $self->{fatlib_dir} : () ),
                @{$self->{dir}}, 
                @INC
            );
        };
    }
    my $mock_obj = bless {}, $mock_class;
    $mock_obj->{target_version} = version->parse("v5.10.1");
    @{$mock_obj}{@keys_params} = @params{@keys_params};
    
    $test->{_mock_obj} = $mock_obj;
    return $mock_obj;
}

sub _construct_test_obj {
    my $test = shift;
    my %params = @_;
    my $test_obj = $test->class()->new(
            core_obj => $test->_create_mock_object(%params)
        ) 
}

sub test_filtering_noncore : Test(2) {
    my $test = shift;
    my $test_obj = $test->_construct_test_obj();

    $test_obj->{core_obj}->{non_CORE_modules} = [
            "Term::Spinner::Color",
            "Local::Test",
            "Getopt::Long",
            "CGI",
            "Module::Build"
        ];
    $test_obj->filter_noncore_dependencies();
    cmp_deeply(
            [
                "Term::Spinner::Color",
                "Local::Test",
                "CGI",
                "Module::Build"
            ],
            set(@{$test_obj->{core_obj}->{_non_core_deps}}),
            "Non-core depndencies should include deprecated ones"
        );

    $test_obj->{core_obj}->{non_CORE_modules} = [
            "Getopt::Long",
            "JSON::PP",
            "Module::Build"
        ];
    $test_obj->{core_obj}->{_non_core_deps} = [];
    $test_obj->filter_noncore_dependencies();
    cmp_deeply(
            [
                "JSON::PP",
                "Module::Build"
            ],
            set(@{$test_obj->{core_obj}->{_non_core_deps}}),
            "Non-core depndencies should include ones appeared later than " .
                "targer Perl version"
        );
}

sub test_filter_non_proj_modules : Test(1) {
    my $test = shift;
    my $class = $test->class();
    my $test_obj = $test->_construct_test_obj(
            proj_dir => [ "t/data/lib" ],
            use_cache => 0
        );

    $test_obj->{core_obj}->{_non_core_deps} = [
            "JSON::PP",
            "Term::Spinner::Color",
            "Local::Test"
        ];
    $test_obj->filter_non_proj_modules();
    cmp_deeply(
            [
                "JSON::PP",
                "Term::Spinner::Color"
            ],
            set(@{$test_obj->{core_obj}->{_non_proj_or_cached}->{non_proj}}),
            "Project dependencies should be properly tracked"
        );
}

1;