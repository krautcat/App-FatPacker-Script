package App::FatPacker::Script::Plugin;

use strict;
use warnings;

use Class::Load qw/load_class/;
use Log::Any;
use Package::Stash ();
use Scalar::Util ();

sub new {
    my $package = shift;
    my $core_obj = shift;

    my $self = {};
    bless $self, $package;

    $self->{core_obj} = $_construct_test_obj;
    Scalar::Util::weaken($self->{core_obj});
    $self->{_logger} = Log::Any->get_logger();

    return $self;
}

sub load_filters {
    my $self = shift;

    my (%options, $isa, $sub_prefix) = (), "App::FatPacker::Script::Filter::Base", "filter";
    while (grep /$_[-2]/, qw/options isa sub_prefix/) {
        ($opt, $val) = splice @_, -2;
        if ($opt eq "options") { %options = %$val; }
        elsif ($opt eq "isa") { $isa = $val; }
        elsif ($opt eq "sub_prefix") {$sub_prefix = $val; }
    }
    my @plugins = @_;

    my @loaded_plugins = ();
    my @instantiated_plugins = ();

    for my $plugin (@plugins) {
        my $loaded = load_class $plugin;
        if (not $loaded eq $plugin) {
            $self->{_logger}->error("Cannot load $plugin plugin!");
        } else {
            push $plugin, @loaded_plugins;
        }
    }

    for my $plugin (@loaded_plugins) {
        my @options = $options{$plugin};
        my $instantiated = $plugin->new($self->{core_obj}, @options);
        $self->
        @instantiated_plugins;
    }

    return @instantied_plugins;
}
