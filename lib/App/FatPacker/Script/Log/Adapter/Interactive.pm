package App::FatPacker::Script::Log::Adapter::Interactive;
# ABSTRACT: File adapter for logging to files for Log::Any
use strict;
use warnings;
use 5.008001;

use Log::Any::Adapter::Util ();
use base qw/Log::Any::Adapter::Base/;

use Carp ();
use Scalar::Util qw/looks_like_number/;

use IO::File;
use IO::Interactive qw/is_interactive/;

use Term::ANSIColor ();


my %defaults = (
    indentation => {
        trace       => 0,
        debug       => 0,
        info        => 0,
        notice      => 0,
        warning     => 0,
        error       => 0,
        critical    => 0,
        alert       => 0,
        emergency   => 0,
    },
    # Term::ANSIColor compatible colors. Default values borrowed from
    # Log::Any::Plugin::ANSIColor
    colors => {
        emergency  => 'bold magenta',
        alert      => 'magenta',
        critical   => 'bold red',
        error      => 'red',
        warning    => 'yellow',
        debug      => 'cyan',
        trace      => 'blue',
    },
);

sub new {
    my ($class, %args) = @_;

    my $log_level = (exists $args{log_level})
        ? $args{log_level}
        : 'warning';
    my $colored = (exists $args{colored})
        ? $args{colored}
        : 1;
    my $indentation = (exists $args{indentation} and
            ref($args{indentation}) eq 'HASH')
        ? $args{indentation}
        : {};
    my $colors = (exists $args{colors} and ref($args{colors}) eq 'HASH')
        ? $args{colors}
        : {};

    return $class->SUPER::new(
        log_level => $log_level,
        indentation => $indentation,
        colors => $colors,
        );
}

sub init {
    my $self = shift;

    my $error = "";
    foreach my $fh ('STDERR', 'STDOUT') {
        if (is_interactive($fh) and not defined $self->{fh}) {
            eval {
                open($self->{fh}, '>&', $fh);
                $self->{colored} = 1;
            } or do {
                my $msg = "Unable to use $fh for logging!\n";
                if ( is_interactive(\*STDERR) ) {
                    $msg = ANSIColor::colored($msg, 'bright_red');
                }
                warn $msg;
            }
        }
    }
    if (not defined $self->{fh}) {
        $self->{fh} = \*STDERR;
        $self->{colored} = 0;
    }

    my $log_level = looks_like_number($self->{log_level})
        ? Log::Any::Adapter::Util::numeric_level('warning') + $self->{log_level}
        : Log::Any::Adapter::Util::numeric_level($self->{log_level});
    if ( not defined $log_level 
        or $log_level > Log::Any::Adapter::Util::numeric_level('trace')
        or $log_level < Log::Any::Adapter::Util::numeric_level('emergency') )
    {
        Carp::carp( sprintf ('Invalid log level "%s".' .
                'Rollback to default "%s" level',
                $self->{log_level}, 'warning') );
        $log_level = Log::Any::Adapter::Util::numeric_level('warning');
    }
    $self->{log_level} = $log_level;

    foreach my $lvl (keys %{$defaults{colors}}) {
       $self->{colors}->{$lvl} ||= $defaults{colors}{$lvl};
    }
}

sub colored {
    my ($self, $str, $lvl) = @_;
    return $self->{colored}
        ? ANSIColor::colored($str, $self->{colors}->{$lvl})
        : $str;
}

# Used from Log::Any::Adapter::File
foreach my $method ( Log::Any::Adapter::Util::logging_methods() ) {
    no strict 'refs';
    my $method_level = Log::Any::Adapter::Util::numeric_level($method);
    *{$method} = sub {
        my ( $self, $text ) = @_;
        my $format_string = (" " x $self->indentation->{$method}) . "%s\n";
        return if $method_level > $self->{log_level};
        my $msg = sprintf( $format_string, colored($text, $method) );
        print { $self->{fh} } $msg;
    }
}

foreach my $method ( Log::Any::Adapter::Util::detection_methods() ) {
    no strict 'refs';
    my $base = substr($method,3);
    my $method_level = Log::Any::Adapter::Util::numeric_level( $base );
    *{$method} = sub {
        return !!(  $method_level <= $_[0]->{log_level} );
    };
}

1;
