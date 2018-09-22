package App::FatPacker::Script::Utils;

use strict;
use warnings;
use 5.010001;
use version 0.77 ();

use Carp qw/croak/;
use Scalar::Util ();

use File::Spec::Functions qw/abs2rel splitdir/;

use Module::CoreList 2.99 ();

use Exporter qw/import/;
our @EXPORT = qw/still_core module_notation_conv lines_of in_ary exclude_ary
    stripspace/;

### Module::CoreList utils

sub still_core {
    my ($module, $ver_since, $ver_until) = (shift, undef, undef);
    croak "No module supplied!" unless defined $module;

    # Parameters are keyword arguments.
    if (scalar(@_) % 2 == 0 and not version::is_strict($_[0])) {
        my %args =  @_;
        ($ver_since, $ver_until) = ($args{'version_since'},
                                    $args{'version_until'});
    }
    # Parameters are positional arguments.
    else {
        ($ver_since, $ver_until) = @_;
    }

    if (Scalar::Util::blessed($ver_since) and $ver_since->isa('version')) {
        $ver_since = $ver_since->numify();
    } elsif (version::is_strict($ver_since)) {
        $ver_since = version->parse($ver_since)->numify();
    } else {
        $ver_since = version->parse('5.005')->numify();
    }
    if (not defined $ver_until) {
        $ver_until = version->parse($^V)->numify();
    }

    if (not Module::CoreList->is_core($module, undef, $ver_since)
        or Module::CoreList->is_deprecated($module, $ver_until)
        or (defined Module::CoreList->removed_from($module)
            and version->parse(Module::CoreList->removed_from($module)) <
                $ver_until    
            )
        )
    {
        return 0    
    }
    else 
    {
        return 1
    }
}

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

