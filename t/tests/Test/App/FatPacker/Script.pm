package Test::App::FatPacker::Script;

use strict;
use warnings;
use diagnostics;

use Test::Most;
use base 'Test::Class';

sub class {
    'App::FatPacker::Script';
}

sub startup : Tests(startup => 1) {
    my $test = shift;
    use_ok $test->class;
}

sub constructor : Tests(4) {
    my $test  = shift;
    my $class = $test->class;
    can_ok $class, 'new';
    {
        ok my $app_obj = App::FatPacker::Script->new(),
            '... and the constructor should succeed';
        local @ARGV = (qw/-q -q -q -v --no-perl-strip t.pl/);
        $app_obj->parse_options(@ARGV);
        ok($app_obj->{verboseness} eq -2, "Check verbosity level");
    }

    {
        my $app_obj = App::FatPacker::Script->new();
        local @ARGV = ("--dir", "t/t,op/t", "stub.pl");
        $app_obj->parse_options(@ARGV);
        use Cwd;
        my $dirname = File::Spec->rel2abs(cwd());
        my $exp_ar = [
            File::Spec->catdir($dirname, 't/t'),
            File::Spec->catdir($dirname, 'op/t'),
        ];
        my $rea_ar = [
            @{$app_obj->{dir}}[-2..-1]
        ];
        is_deeply($rea_ar, $exp_ar, "Directory for appending to \@INC");
    }
}

1;