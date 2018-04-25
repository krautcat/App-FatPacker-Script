package Test::App::FatPacker::Script::Parsing;

use strict;
use warnings;
use diagnostics;

use Cwd;

use Test::More;
use base 'Test::Class';

sub class {
    'App::FatPacker::Script';
}

sub before : Test(setup) {
    my $test = shift;
    my $class = $test->class();
    $test->{app_obj} = $class->new();
}

sub _parse_args {
    my ($test, @args) = @_;
    $test->{app_obj}->parse_options(@args, "xt/bin/stub.pl");
}

sub parsing_verbosity : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "-q", "-q", "-q", "-v", 
            "--no-perl-strip");
    
    is(
        $test->{app_obj}->{verboseness},
        -2, 
        "Check verbosity level"
    );
}

sub parsing_base_directory : Tests(2) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "xt");
    
    my $dirname = File::Spec->rel2abs(cwd());
    is_deeply(
        $test->{app_obj}->{proj_dir},
        [ File::Spec->catdir($dirname, "xt", "lib") ],
        "Project directory must consider base directory"
    );
    is(
        $test->{app_obj}->{fatlib_dir},
        File::Spec->catdir($dirname, "xt", "fatlib"),
        "Fatlib directory must consider base directory"
    );
}

sub directories_with_modules : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "xt",
            "--dir",
                "extlib,newlib");
    
    my $dirname = File::Spec->rel2abs(cwd());
    is_deeply(
        [
            @{$test->{app_obj}->{dir}}[-2..-1]
        ],
        [
            File::Spec->catdir($dirname, "xt", 'extlib'),
            File::Spec->catdir($dirname, "xt", 'newlib'),
        ],
        "Directory for appending to \@INC"
    );
}

sub fatlib_directory_by_default : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "xt",
            "--dir",
                "extlib");

    my $cwd = File::Spec->rel2abs(cwd());
    my $fatlib = File::Spec->catdir($cwd, "xt", 'fatlib');
    my @grepped_fatlib = grep { $_ eq $fatlib } @{$test->{app_obj}->{dir}}; 
    is(
        $grepped_fatlib[0],
        $fatlib, 
        "Fatlib directory in list of directories with default params"
    );
}

sub fatlib_directory_no_use_cache : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "xt",
            "--dir",
                "extlib",
            "--no-use-cache");

    my $cwd = File::Spec->rel2abs(cwd());
    my $fatlib = File::Spec->catdir($cwd, "xt", 'fatlib');
    my @grepped_fatlib = grep { $_ eq $fatlib } @{$test->{app_obj}->{dir}}; 
    is(
        scalar(@grepped_fatlib),
        0,
        "Fatlib directory is not in list of directories with '--no-use-cache' param"
    );
}

sub proj_dirs_in_dir_array : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "xt",
            "--dir",
                "extlib",
            "--proj-dir",
                "projlib,lib");

    my $cwd = File::Spec->rel2abs(cwd());
    is_deeply(
        [
            @{$test->{app_obj}->{dir}}[0..1]
        ],
        [
            File::Spec->catdir($cwd, "xt", 'projlib'),
            File::Spec->catdir($cwd, "xt", 'lib'),
        ],
        "Project directories must be in front of dir array"
    );
}

sub test_including_modules : Tests(2) {
    my $test = shift;
    $test->_parse_args(
            "--non-core",
                "JSON::PP,Log::Any",
            "--includes",
                "Term::ANSIColor,IO::Uncompress::Unzip");
    is_deeply(
        $test->{app_obj}->{non_CORE},
        [
            "JSON::PP",
            "Log::Any",
        ],
        "Non-core modules' array should contain two modules"
    );
    is_deeply(
        $test->{app_obj}->{forced_CORE},
        [
            "Term::ANSIColor",
            "IO::Uncompress::Unzip",
        ],
        "Forced core modules' array should contain two modules"
    );
}

sub test_result_file : Tests(1) {
    my $test = shift;
    my $cwd = File::Spec->rel2abs(cwd());
    $test->_parse_args(
            "--base",
                "xt",
            "--to",
                "stub_fatpacked.pl");
    is(
        $test->{app_obj}->{result_file},
        File::Spec->catdir($cwd, "xt", "stub_fatpacked.pl")
    );
}

sub use_perl_strip : Tests(1) {
    my $test = shift;
    $test->_parse_args();
    isa_ok(
        $test->{app_obj}->{perl_strip},
        "Perl::Strip"
    );
}

sub logger_adapter_interactive : Tests(3) {
    my $test = shift;
    $test->_parse_args();
    isa_ok(
        $test->{app_obj}->{logger}->{adapter},
        "App::FatPacker::Script::Log::Adapter::Interactive"
    );
    is(
        $test->{app_obj}->{logger}->{adapter}->{colored},
        0,
        "Interactive adapter shouldn't color output in non-interactive mode"
    );
    is(
        $test->{app_obj}->{logger}->{adapter}->{fh},
        \*main::STDERR,
        "Filehandle should point to STDERR"
    );
}

sub logger_adapter_file : Tests(4) {
    my $test = shift;
    $test->_parse_args(
            "--output",
                "xt/tmp.log");
    isa_ok(
        $test->{app_obj}->{logger}->{adapter},
        "App::FatPacker::Script::Log::Adapter::File"
    );
    is(
        $test->{app_obj}->{logger}->{adapter}->{file}->opened(),
        1,
        "File should be possible to open"
    );
    is(
        $test->{app_obj}->{logger}->{adapter}->{mode},
        '>',
        "Mode is for writing"
    );
    is(
        $test->{app_obj}->{logger}->{adapter}->{binmode},
        "utf8",
        "File should be opened in ':utf8' mode"
    );
}

1;