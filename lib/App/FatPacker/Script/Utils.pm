package App::FatPacker::Script::Utils;

use strict;
use warnings;
use 5.010001;

use File::Spec::Functions qw/abs2rel splitdir/;

use Exporter qw/import/;
our @EXPORT = qw/lines_of module_notation_conv in_ary exclude_ary stripspace/;

### Misc utils

sub lines_of {
    map +(chomp,$_)[1], do { local @ARGV = ($_[0]); <> };
}

sub stripspace {
    my ($text) = @_;
    $text =~ /^(\s+)/ && $text =~ s/^$1//mg;
    $text;
}

sub module_notation_conv {
    # Conversion of double-coloned module notation (with :: as separator) to
    # platform-dependent file representation.
    # Direction:
    #   1 - filename >> dotted
    #   0 - dotted >> filename
    # Note: subroutine currently supports only Unix-like systems
    my ($namestring, %args) = @_;
    my $direction = 1;
    if (exists $args{direction}) {
        if ($args{direction} eq 'to_dotted'
            or $args{direction} eq 'to_fname')
        {
            $direction = $args{direction} eq 'to_dotted' ? 1 : 0;
        }
        else
        {
            return;
        }
    }
    my $relative = (exists $args{relative}) 
        ? $args{relative}
        : 0;
    my $base = (exists $args{base} and not $args{base} eq "")
        ? $args{base}
        : $INC[0];

    my %separators = (  MSWin32 => '\\',
                        Unix    => '/'  );
    my $path_separator = $separators{$^O} || $separators{Unix};

    if ($direction) {
        my $mod_path = $namestring;
        if (index($namestring, $path_separator) && $relative) {
            $mod_path = abs2rel($namestring, $base);
        }
        my @mod_path_parts = splitdir $mod_path;
        if ($mod_path_parts[0] eq '..') {
            shift @mod_path_parts;
        }
        $mod_path_parts[-1] =~ s/(.*)\.pm$/$1/;
        return join '::', @mod_path_parts;
    } else {
        my @mod_name_parts = split '::', $namestring;
        my $mod_path = join($path_separator, @mod_name_parts) . ".pm";
        if (exists $args{absolute} and $args{absolute}) {
            $mod_path = "${base}${path_separator}${mod_path}";
        }
        return $mod_path;
    }
}

sub in_ary {
    my ($el, $array) = @_;
    return (grep { $_ eq $el } @$array) ? 1 : 0;
}

sub exclude_ary {
    my ($main, $exclude) = @_;
    my %exclude_hash = map { $_ => 1 } @$exclude;
    return (grep { not $exclude_hash{$_} } @$main);
}