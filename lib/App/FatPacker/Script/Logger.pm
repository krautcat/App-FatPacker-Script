package App::FatPacker::Script::Logger;

use strict;
use warnings;

sub log {
    my ($self, $msg, $level, %args) = (shift, shift, undef, ());
    if (scalar(@_) % 2 == 0) {
        %args = @_;
    } else {
        $level = shift;
        %args = @_;
    }
    return unless (defined $msg);

    my $arg_extractor = sub {
        my ($arg_name, $default_value) = @_;
        if (wantarray) {
            return
                exists $args{$arg_name}
                ? ( defined reftype($args{$arg_name}) and
                    reftype($args{$arg_name}) eq 'ARRAY' )
                    ? @{$args{$arg_name}}
                    : ($args{$arg_name})
                : ();
        } elsif (defined wantarray) {
            return
                exists $args{$arg_name}
                ? $args{$arg_name}
                : $default_value;
        } else {
            return
        }
    };

    my @msgs = $arg_extractor->('msgs');
    my @attrs = $arg_extractor->('attrs');

    my $tabs = $arg_extractor->('tabs', 0);
    my $colored = $arg_extractor->('colored', 1);

    # Level to int mapping
    my %log_levels = (  "info"      => -1,
                        "warning"   => 0,
                        "critical"  => 1,   );
    # Assume terminal emulator or terminal supports 256 colors
    my %log_colors = (  "info"      => 'bright_green',
                        "warning"   => 'bright_yellow',
                        "critical"  => 'bright_red',    );

    if ($colored == 0 and $tabs == 0) {
        $tabs = 3;
    }
    if (not defined $level or $level eq '' or not exists $log_levels{$level}) {
        $level = "warning";
    }
    if ($self->{colored_logs} and $colored) {
        $msg = colored $msg, $log_colors{$level}, @attrs;
    }
    $msg = (" " x $tabs) . $msg . (" " . join " ", @msgs);
    if ($self->{verboseness} >= $log_levels{$level}) {
        say { $self->{output} } $msg;
    }
}
