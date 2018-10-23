package App::FatPacker::Script::Plugin::Filter::Base;

use strict;
use warnings;

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless {}, $class;

    $self->{core_obj} = $params{core_obj} || die "Missing core object";
    Scalar::Util::weaken($self->{core_obj});

    $self->{_logger} = Log::Any->get_logger();

    return $self;
}

1;
