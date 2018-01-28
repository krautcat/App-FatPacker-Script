package App::FatPacker::Script::Log::Adapter::Interactive;
# ABSTRACT: File adapter for logging to files for Log::Any
use strict;
use warnings;
use 5.008001;

use Log::Any::Adapter::Util ();
use base qw/Log::Any::Adapter::Base/;

use Carp ();

use IO::File;
use IO::Interactive;

sub new {
    my ($class, %args) = @_;

    my $log_level = (exists $args{log_level})
        ? $args{log_level}
        : 'warning';
    my $colors = (exists $args{colors} and ref($args{colors}) eq 'HASH')
        ? $args{colors}
        : {};

    return $class->SUPER::new(
        log_level => $log_level,
        colors => $colors
        );
}

sub init {
    my $self = shift;

    my $error = "";
    foreach my $fh (STDERR, STDOUT) {
        if (is_interactive($fh) and not defined $self->{fh}) {
            eval {
                open($self->{fh}, '>&', $fh);
                $self->{colored} = 1;
            } or do {
                $error .= "Unable to use $fh for logging!\n"
            }
        }
    }
    if (not defined $self->{fh}) {
        $self->{fh} = \*STDERR;
        $self->{colored} = 0;
    }

    my $log_level = Log::Any::Adapter::Util::numeric_level($self->{log_level});
    if (not defined $log_level) {
        Carp::carp( sprintf ('Invalid log level "%s".' .
                'Rollback to default "%s" level',
                $self->{log_level}, 'warning') );
        $log_level = Log::Any::Adapter::Util::numeric_level('warning');
    }
    $self->{log_level} = $log_level;

    # Term::ANSIColor compatible colors. Default values borrowed from
    # Log::Any::Plugin::
    my %default_colors = (
        emergency  => 'bold magenta',
        alert      => 'magenta',
        critical   => 'bold red',
        error      => 'red',
        warning    => 'yellow',
        debug      => 'cyan',
        trace      => 'blue',
    );

    foreach my $lvl (keys %default_colors) {
       $self->{colors}->{$lvl} ||= $default_colors{$lvl};
    }
}

1;
