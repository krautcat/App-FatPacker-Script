package Test::App::FatPacker::Script::Plugin;

use strict;
use warnings;

use parent 'Test::Class';

use Test::More;
use Test::Deep;

use App::FatPacker::Script::Plugin;

sub class {
    return "App::FatPacker::Script::Plugin";
}

sub traverse_options : Test(no_plan) {
    my $test = shift;
    my $func_name = "_transform_opts";
    my $func = \&{ $test->class() . "::${func_name}"};

    my @plugins = ("App::FatPacker::Script::Plugin::Filter::Core");
    my @params = (@plugins, options => { core_obj => "obj_stub" } );
    my ($plugins, $options, $isa, $sub_prefix) = $func->(@params);  
    is_deeply(
        $plugins,
        \@plugins,
        "Plugins parameter is ok"
    );
    use DDP;
    p $options;
    cmp_deeply(
        $options,
        {
            $plugins[0] => $params[-1]
        },
        "Options for plugins are ok"
    );
    is($isa, "App::FatPacker::Script::Plugin::Filter::Base",
        "Plugin base class is fatlib_directory_by_default");
    is($sub_prefix, "filter", "Subroutine prefix is default"); 
}

1;
