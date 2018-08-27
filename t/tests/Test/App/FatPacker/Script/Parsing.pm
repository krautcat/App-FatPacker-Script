package Test::App::FatPacker::Script::Parsing;

use strict;
use warnings;
use diagnostics;

use Cwd;

use Test::More;
use base 'Test::Class';

use App::FatPacker::Script;

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
    $test->{app_obj}->parse_options(@args, "t/data/bin/stub.pl");
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
                "t/data");
    
    my $dirname = File::Spec->rel2abs(cwd());
    is_deeply(
        $test->{app_obj}->{core_obj}->{proj_dir},
        [ File::Spec->catdir($dirname, "t", "data", "lib") ],
        "Project directory must consider base directory"
    );
    is(
        $test->{app_obj}->{core_obj}->{fatlib_dir},
        File::Spec->catdir($dirname, "t", "data", "fatlib"),
        "Fatlib directory must consider base directory"
    );
}

sub directories_with_modules : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "t/data",
            "--dir",
                "extlib,newlib");
    
    my $dirname = File::Spec->rel2abs(cwd());
    is_deeply(
        [
            @{$test->{app_obj}->{core_obj}->{dir}}[-2..-1]
        ],
        [
            File::Spec->catdir($dirname, "t", "data", 'extlib'),
            File::Spec->catdir($dirname, "t", "data", 'newlib'),
        ],
        "Directory for appending to \@INC"
    );
}

sub fatlib_directory_by_default : Tests(1) {
    my $test = shift;
    $test->_parse_args(
            "--base", 
                "t/data",
            "--dir",
                "extlib");

    my $cwd = File::Spec->rel2abs(cwd());
    my $fatlib = File::Spec->catdir($cwd, "t", "data", 'fatlib');
    my @grepped_fatlib = grep { $_ eq $fatlib } @{$test->{app_obj}->{core_obj}->{dir}}; 
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
                "t/data",
            "--dir",
                "extlib",
            "--no-use-cache");

    my $cwd = File::Spec->rel2abs(cwd());
    my $fatlib = File::Spec->catdir($cwd, "t", "data", 'fatlib');
    my @grepped_fatlib = grep { $_ eq $fatlib } @{$test->{app_obj}->{core_obj}->{dir}}; 
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
                "t/data",
            "--dir",
                "extlib",
            "--proj-dir",
                "projlib,lib");

    my $cwd = File::Spec->rel2abs(cwd());
    is_deeply(
        [
            @{$test->{app_obj}->{core_obj}->{dir}}[0..1]
        ],
        [
            File::Spec->catdir($cwd, "t", "data", 'projlib'),
            File::Spec->catdir($cwd, "t", "data", 'lib'),
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
        $test->{app_obj}->{core_obj}->{non_CORE_modules},
        [
            "JSON::PP",
            "Log::Any",
        ],
        "Non-core modules' array should contain two modules"
    );
    is_deeply(
        $test->{app_obj}->{core_obj}->{forced_CORE_modules},
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
                "t/data",
            "--to",
                "stub_fatpacked.pl");
    is(
        $test->{app_obj}->{core_obj}->{output_file},
        File::Spec->catdir($cwd, "t", "data", "stub_fatpacked.pl")
    );
}

sub use_perl_strip : Tests(1) {
    my $test = shift;
    $test->_parse_args();
    isa_ok(
        $test->{app_obj}->{core_obj}->{perl_strip},
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
                "t/data/tmp.log");
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
