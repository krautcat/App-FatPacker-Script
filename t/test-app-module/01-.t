#!/usr/bin/env perl
# package Test::App::Module;

use Test::More qw/no_plan/;

use App::FatPacker::Script;

use File::Spec;

{
    my $app_obj = App::FatPacker::Script->new();
    local @ARGV = (qw/-q -q -q -v --no-perl-strip t.pl/);
    $app_obj->parse_options(@ARGV);
    ok($app_obj->{verboseness} eq -2, "Check verbosity level");
}

{
    my $app_obj = App::FatPacker::Script->new();
    local @ARGV = qw|--dir t/t,op/t stub.pl|;
    $app_obj->parse_options(@ARGV);
    use Cwd;
    $dirname = File::Spec->rel2abs(cwd());
    my $exp_ar = [
        File::Spec->catdir($dirname, 't/t'),
        File::Spec->catdir($dirname, 'op/t'),
    ];
    my $rea_ar = [
        @{$app_obj->{dir}}[-2..-1]
    ];
    is_deeply($rea_ar, $exp_ar, "Directory for appending to \@INC");
}
