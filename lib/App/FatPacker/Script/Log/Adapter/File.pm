package App::FatPacker::Script::Log::Adapter::File;
# ABSTRACT: File adapter for logging to files for Log::Any
use strict;
use warnings;
use 5.008001;

use Log::Any::Adapter::Util ();
use base qw/Log::Any::Adapter::Base/;

use Carp ();
use Scalar::Util qw/looks_like_number/;

use Config;

use Fcntl qw/:flock/;
use IO::File ();

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
    }
)

sub new {
    my ($class, $file, %args) = @_;

    # Defaultize arguments
    my $log_level = (exists $args{log_level})
        ? $args{log_level}
        : 'warning';
    my $binmode = (exists $args{binmode})
        ? $args{binmode}
        : 'utf8';
    my $indentation = (exists $args{indentation} and
            ref($args{indentation}) eq 'HASH')
        ? $args{indentation}
        : {}};
    my $timestamp = (exists $args{timestamp} and $args{timestamp})
        ? $args{timestamp}
        : undef;
    
    return $class->SUPER::new(
        file => $file,
        log_level => $log_level,
        binmode => $binmode,
        indentation => $indentation,
        timestamp => $timestamp,
        %args);
}

sub init {
    my $self = shift;

    my %open_modes_aliases = ();
    my %open_modes = ();
    foreach my $m (['<', 'r'], ['>', 'w', 'write'], ['>>', 'a', 'append'],
        ['+<', 'r+'], ['+>', 'w+'], ['+>>', 'a+']) {
        $open_modes{$m->[0]} = 1;
        @open_modes_aliases{@$m[1 .. $#$m]} = ($m->[0]) x (scalar(@$m) - 1);
    }

    my %bin_modes = ();
    foreach my $l ('unix', 'stdio', 'crlf', 'perlio', 'utf8', 'bytes', 'raw') {
        @bin_modes{$l, ":$l"} = (1, 1);
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

    my $mode = (exists($self->{mode}) and $self->{mode} ne '')
        ? $self->{mode}
        : '>';
    if ($open_modes{$mode} and $mode ne '<') {
        $self->{mode} = $open_modes{$mode};
    } elsif (exists $open_modes_aliases{$mode} and $open_modes_aliases{$mode} ne '<') {
        $self->{mode} = $open_modes_aliases{$mode};
    } else {
        $self->{mode} = '>';
    }
    
    my $filename = $self->{file};
    $self->{file} = IO::File->new($filename, $mode);
    Carp::croak "Can't open $filename for logging" unless defined $self->{file};
    
    my $binmode = exists $bin_modes{$self->{binmode}}
        ? substr($self->{binmode}, 0, 1) eq ':'
            ? $self->{binmode}
            : ":" . $self->{binmode}
        : ":utf8";
    $self->{file}->binmode($binmode);
    $self->{file}->autoflush(1);

    # File locking possibility
    $self->{__has_flock} = $Config{d_flock} || $Config{d_fcntl_can_lock} || $Config{d_lockf};

    foreach my $method ( Log::Any::Adapter::Util::logging_methods() ) {
        $indentation->{$method} ||= $default{$method};
    }
}

sub timestamp {
    my $self = shift;
    return $self->{timestamp}
        ? sprintf "[%s] ", scalar(localtime)
        : "";
}

# Used from Log::Any::Adapter::File
foreach my $method ( Log::Any::Adapter::Util::logging_methods() ) {
    no strict 'refs';
    my $method_level = Log::Any::Adapter::Util::numeric_level($method);
    my $format_string = "%s" . (" " x $self->indentation->{$method}) . "%s\n"
    *{$method} = sub {
        my ( $self, $text ) = @_;
        return if $method_level > $self->{log_level};
        my $msg = sprintf($format_string, $self->timestamp(), $text);
        flock($self->{file}, LOCK_EX) if $self->{__has_flock};
        $self->{file}->print($msg);
        flock($self->{file}, LOCK_UN) if $self->{__has_flock};
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
