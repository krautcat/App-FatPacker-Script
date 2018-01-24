package App::FatPacker::Script::Log::Adapter::File;
# ABSTRACT: File adapter for logging to files for Log::Any
use strict;
use warnings;
use 5.008001;

use Log::Any::Adapter::Util ();
use base qw/Log::Any::Adapter::Base/;

use Carp ();

use IO::File ();

sub new {
    my ($class, $file, @args) = @_;

    # Defaultize arguments
    my $log_level = (exists $args{log_level})
        ? $args{log_level}
        : 'warning';
    my $binmode = (exists $args{binmode})
        ? $args{binmode}
        : 'utf8';
    
    return $class->SUPER::new(
        file => $file,
        log_level => $log_level,
        binmode => $binmode,
        @args);
}

sub init {
    my $self = shift;

    my %open_modes = (
        write   => 1,
        append  => 1,
    );
    foreach my $m ('<')

    my %bin_modes = ();
    foreach my $l ('unix', 'stdio', 'crlf', 'perlio', 'utf8', 'bytes', 'raw') {
        @bin_modes{$l, ":$l"} = (1, 1);
    }

    my $log_level = Log::Any::Adapter::Util::numeric_level($self->{log_level});
    if (not defined $log_level) {
        Carp::carp( sprintf ('Invalid log level "%s".' .
                'Rollback to default "%s" level',
                $self->{log_level}, 'warning');
        $log_level = Log::Any::Adapter::Util::numeric_level('warning');
    }
    
    my $filename = $self->{file};
    my $mode = exists $open_modes{$self->{mode}} and $self->{mode}
        ? $open_modes{$self->{mode}}
        : 'r'
    $self->{file} = IO::File->new($filename, $mode);
    Carp::croak "Cannot open $filename for logging" unless defined $self->{file};
    
    my $binmode = substr($self->{binmode}, 0, 1) eq ':'
        ? $self->{binmode}
        : ":$self->{binmode}";
    $self->{file}->binmode($binmode);
    $self->{file}->autoflush(1);
}
