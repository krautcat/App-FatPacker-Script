package App::FatPacker::Script::Plugin;

use strict;
use warnings;

use Class::Load ();
use Log::Any;
use Package::Stash ();
use Scalar::Util   ();

sub new {
    my $package = shift;
    my $self    = {};

    bless $self, $package;

    $self->{_logger} = Log::Any->get_logger();

    return $self;
}

sub load_plugins {
    my $self = shift;

    my ( @options, %options ) = ();
    my ( $isa, $sub_prefix ) =
      ( "App::FatPacker::Script::Plugin::Filter::Base", "filter" );
    while ( grep /$_[-2]/, qw/options isa sub_prefix/ ) {
        my ( $opt, $val ) = splice @_, -2;
        if ( $opt eq "options" ) {
            if (ref($val) eq 'ARRAY') {
                @options = @$val;
            } elsif (ref($val) eq 'HASH') {
                my %hash_opts = %$val;
                push @options, %hash_opts;
            } else {
                push @options, $val;
            }
        }
        elsif ( $opt eq "isa" )        { $isa        = $val; }
        elsif ( $opt eq "sub_prefix" ) { $sub_prefix = $val; }
    }
    my @plugins = @_;

    %options = @options if scalar @options % 2 == 0;

    # If single plugin is passed, treat %options hash as options
    if ( scalar @plugins == 1
        and ( scalar @options % 2 == 1 or not exists $options{ $plugins[0] } ) )
    {
        $options{ $plugins[0] } = \@options;
        delete @options{ grep !/^$plugins[0]$/, keys %options };
    }
    else {
        %options = @options;
    }

    my @loaded_plugins       = ();
    my @instantiated_plugins = ();

    for my $plugin (@plugins) {
        my $loaded = Class::Load::load_class $plugin;
        if ( not $loaded eq $plugin ) {
            $self->{_logger}->error("Cannot load $plugin plugin!");
        }
        else {
            push @loaded_plugins, $plugin;
        }
    }

    for my $plugin (@loaded_plugins) {
        my @options = $options{$plugin};
        push @instantiated_plugins, $plugin->new(@options);
    }

    return @instantiated_plugins;
}

1;
