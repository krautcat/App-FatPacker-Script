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

sub parsing_verbosity : Tests(1) {
    my $test = shift;
    
    my $app_obj;
    local @ARGV;

    @ARGV = ("-q", "-q", "-q", "-v", "--no-perl-strip", "t/bin/stub.pl");
    $app_obj = App::FatPacker::Script->new();
    $app_obj->parse_options(@ARGV);
    ok($app_obj->{verboseness} eq -2, "Check verbosity level");
}

sub parsing_directories : Tests(no_plan) {
    my $test = shift;
    
    my $app_obj;
    local @ARGV;

    use Cwd;

    @ARGV = ("--dir", "extlib,newlib", "t/bin/stub.pl");
    $app_obj = App::FatPacker::Script->new();
    $app_obj->parse_options(@ARGV);
    my $dirname = File::Spec->rel2abs(cwd());
    my $exp_ar = [
        File::Spec->catdir($dirname, 'extlib'),
        File::Spec->catdir($dirname, 'newlib'),
    ];
    my $rea_ar = [
        @{$app_obj->{dir}}[-2..-1]
    ];
    is_deeply($rea_ar, $exp_ar, "Directory for appending to \@INC");



    my $fatlib;
    my @grepped_fatlib;

    @ARGV = ("--dir", "extlib", "t/bin/stub.pl");
    $app_obj = App::FatPacker::Script->new();
    $app_obj->parse_options(@ARGV);
    $fatlib = File::Spec->catdir($dirname, 'fatlib');
    @grepped_fatlib = grep { $_ eq $fatlib } @{$app_obj->{dir}}; 
    is($fatlib, $grepped_fatlib[0],
            "Fatlib directory in list of directories with default params");

    
    @ARGV = ("--dir", "extlib", "--no-use-cache", "t/bin/stub.pl");
    $app_obj = App::FatPacker::Script->new();
    $app_obj->parse_options(@ARGV);
    $fatlib = File::Spec->catdir($dirname, 'fatlib');
    @grepped_fatlib = grep { $_ eq $fatlib } @{$app_obj->{dir}}; 
    is(scalar(@grepped_fatlib), 0,
            "Fatlib directory is not in list of directories with '--no-use-cache' param");


    @ARGV = ("--dir", "extlib", "--proj-dir", "projlib", "lib", "t/bin/stub.pl");
    $app_obj = App::FatPacker::Script->new();
    $app_obj->parse_options(@ARGV);
    my $dirname = File::Spec->rel2abs(cwd());
    my $exp_ar = [
        File::Spec->catdir($dirname, 'projlib'),
        File::Spec->catdir($dirname, 'lib'),
    ];
    my $rea_ar = [
        @{$app_obj->{dir}}[0..1]
    ]; 
    is_deeply($rea_ar, $exp_ar,
            "Project directories must be in front of dir array");

    @ARGV = ("--non-core", "Foo::Bar,JSON::PP,Log::Any",
            "--includes", "Term::ANSIColor", "IO::Uncompress::Unzip")
}


1;