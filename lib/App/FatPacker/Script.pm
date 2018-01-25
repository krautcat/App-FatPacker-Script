package App::FatPacker::Script;
# ABSTRACT: FatPacker for scripts
use strict;
use warnings;
use 5.010001;

use Data::Printer;

use Config;
use version;
use List::Util qw/uniq/;
use Scalar::Util qw/reftype/;
use Storable qw/fd_retrieve store_fd/;

use IO::File;
use IO::Pipe;
use IO::Interactive qw/is_interactive/;
use Term::ANSIColor;

use Cwd qw/cwd/;
use File::Find qw/find/;
use File::Copy qw/copy/;
use File::Path qw/make_path remove_tree/;
use File::Spec::Functions qw/
    catdir catpath
    splitdir splitpath
    rel2abs abs2rel
    file_name_is_absolute
    /;

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;

use Log::Any;
use Log::Any::Adapter;
use Log::Any::Plugin;

# use Perl::Strip;
use Module::CoreList;
use App::FatPacker;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @_;

    Getopt::Long::Configure("bundling");

    # Default values
    my @dirs = ("lib", "fatlib", "local", "extlib");
    my @proj_dirs = ();
    my (@additional_core, @non_core) = (() , ());
    my $target_version = $];

    # Check, if passed version exists or not
    my $version_handler = sub {
        my ($opt_obj, $version_val) = @_;
        my $target = version->parse($version_val || $target_version)->numify;
        $target_version = exists $Module::CoreList::version{$target}
            ? $target
            : $target_version;
    };

    GetOptions
        "d|dir=s@"      => \@dirs,
        "b|base=s"      => \(my $base = cwd),
        "f|fatlib-dir=s"
                        => \(my $fatlib_dir = "fatlib"),
        "p|proj-dir=s@" => \@proj_dirs,
        "i|includes=s@" => \@additional_core,
        "n|non-core=s@" => \@non_core,
        "h|help"        => sub { pod2usage(1) },
        "o|output=s"    => \(my $output),
        "q|quiet+"      => \(my $quiet = 0),
        "v|verbose+"    => \(my $verbose = 0),
        "s|strict"      => \(my $strict),
        "V|version"     => sub { printf "%s %s\n", __PACKAGE__, __PACKAGE__->VERSION; exit },
        "t|target=s"    => $version_handler,
        "color!"        => \(my $color = 1),
        "use-cache!"    => \(my $cache = 1),
        "shebang=s"     => \(my $custom_shebang),
        "exclude-strip=s@" => \(my $exclude_strip),
        "no-strip|no-perl-strip" => \(my $no_perl_strip),
        or pod2usage(2);

    $self->{script}     = shift @ARGV or do { warn "Missing scirpt.\n"; pod2usage(2) };
    push @{$self->{dir}}, map { rel2abs $_, $base }
                          split( /,/, join(',', @dirs) );
    push @{$self->{forced_CORE}}, split( /,/, join(',', @additional_core) );
    push @{$self->{non_CORE}}, split( /,/, join(',', @non_core) );
    push @{$self->{proj_dir}},
        scalar @proj_dirs
        ? ( map { rel2abs $_, $base } @proj_dirs )
        : ( rel2abs "lib", $base );
    $self->{fatlib_dir} = rel2abs $fatlib_dir, $base;
    $self->{strict}     = $strict;
    $self->{target}     = $target_version;
    $self->{perl_strip} = $no_perl_strip ? undef : Perl::Strip->new;
    $self->{custom_shebang} = $custom_shebang;
    $self->{exclude_strip}  = [ map { qr/$_/ } @{$exclude_strip || []} ];
    $self->{exclude}    = [];
    $self->{use_cache}  = $cache;

    if (in_ary($self->{fatlib_dir}, $self->{dir}) and !$self->{use_cache}) {
        $self->{dir} = [ grep { $_ ne $self->{fatlib_dir} } @{$self->{dir}} ];
    }

    # Concatenate project directories at the beginning of array of directories
    # to look up modules and then remove duplicates.
    unshift @{$self->{dir}}, @{$self->{proj_dir}};
    @{$self->{dir}} = uniq @{$self->{dir}};

    # Setting output descriptor. Try to open file supplied from command line.
    # options. If opening failed, show message to user and return to fallback
    # default mode (logging to STDERR).
    my $log_set = 0;
    if (defined $output and $output ne '') {
        eval {
            Log::Any::Adapter->set('File', $output, log_level => 'debug');
            $log_set = 1;
        } or do {
            my $msg = "Can't open $output for logging!";
            if ( is_interactive(\*STDERR) ) {
                $msg = colored $msg, 'bright_red';
            }
            say STDERR $msg;
        }
    }

    if (not $log_set) {
        if ( is_interactive(\*STDERR) ) {
            Log::Any::Adapter->set('Stderr');
            Log::Any::Plugin->add('ANSIColor');
        } elsif ( is_interactive(\*STDOUT) ) {
            Log::Any::Adapter->set('Stdout');
            Log::Any::Plugin->add('ANSIColor');
        } else {
            Log::Any::Adapter->set('Stderr');
        }
    }
    $self->{colored_logs} = (is_interactive($self->{output}) and $color) ? 1 : 0;
    $self->{verboseness} = $verbose - $quiet;
    $self->{logger} = Log::Any->get_logger();

    return $self;
}

sub trace_noncore_dependencies {
    my ($self, %args) = @_;

    my @opts = ($self->{script});
    if ($self->{quiet}) {
        push @opts, '2>/dev/null';
    }
    my $trace_opts = '>&STDOUT';

    local $ENV{PERL5OPT} = join ' ',
        ( $ENV{PERL5OPT} || () ), '-MApp::FatPacker::Trace=' . $trace_opts;
    local $ENV{PERL5LIB} = join ':',
        @{$self->{dir}}, ( $ENV{PERL5LIB} || () );

    my %replace = (
        '/'   => '::',
        '.pm' => '',
        '\n'  => '',
    );
    return
        map { $args{to_packlist} ? s!::!/!gr . ".pm" : $_ }
        grep { not Module::CoreList->is_core($_, undef, $self->{target}) }
        sort { $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger }
        map { s!(/|.pm|\n)!$replace{$1} // ''!egr } qx/$^X @opts/;   ## no critic
}

sub filter_non_proj_modules {
    my ($self, $modules) = @_;

    my $pid = open(my $pipe, "-|");
    defined($pid) or die "Can't fork for filtering project modules: $!\n";

    if ($pid) {
        my @child_output = (<$pipe>);
        chomp @child_output;
        return @child_output;
    } else {
        local @INC = (@{$self->{dir}}, @INC);
        for my $non_core (@$modules) {
            eval {
                require $non_core;
                1;
            } or do {
                $self->{logger}->warn("Cannot load $non_core module: $@");
            };
            if ( not grep {
                    $INC{$non_core} =~ m!$_/$non_core!
                } @{$self->{dir}} )
            {
                say $non_core;
            }
        }
        exit 0;
    }
}

sub filter_xs_modules {
    my ($self, $modules) = @_;

    my $pid = open(my $pipe_dyna, "-|");
    defined($pid) or die "Can't fork for filtering XS modules: $!\n";

    if ($pid) {
        my @child_output = (<$pipe_dyna>);
        chomp @child_output;
        return @child_output;
    } else {
        use DynaLoader;
        local @INC = (@{$self->{dir}}, @INC);
        for my $module_file (@$modules) {
            my $module_name = $module_file =~ s!/!::!gr =~ s!.pm$!!r;
            eval {
                require $module_file;
                1;
            } or do {
                $self->{logger}->warn("Failed to load ${module_file}: $@");
            };
            if ( grep { $module_name eq $_ } @DynaLoader::dl_modules ) {
                say $module_file;
            }
        }
        exit 0;
    }
}

sub add_forced_core_dependenceies {
    my ($self, $noncore) = @_;
    push @$noncore, @{$self->{forced_CORE}};
    if (wantarray) {
        return (sort {
                $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger
            } @$noncore);
    } elsif (defined wantarray) {
        return $noncore;
    } else {
        return;
    }
}

sub packlist {
    my ($self, $deps) = @_;
    my %h = $self->packlists_containing($deps);
    $self->{logger}->info(">>>>> non-XS orphans");
    $self->{logger}->info($_) for grep { my $m = $_; not grep { $_ eq $m } @{$self->{xsed_deps}} } @{$h{orphaned}};
    $self->{logger}->info(">>>>> XS orphans");
    $self->{logger}->info($_) for grep { my $m = $_; grep { $_ eq $m } @{$self->{xsed_deps}} } @{$h{orphaned}};
    return ( keys %{$h{loadable}} );
}

sub packlists_containing {
    my ($self, $module_files) = @_;
    my @packlists;

    my $pipe = IO::Pipe->new();
    my $pid = fork;
    defined($pid) or die "Can't fork for loading modules: $!\n";

    if ($pid) {
        $pipe->reader();
        return %{ fd_retrieve($pipe) };
    } else {
        # Exclude paths controlled by our project
        local @INC = (exclude_ary($self->{dir}, $self->{proj_dir}) , @INC);
        my @loadable = ();
        for my $module (@$module_files) {
            eval {
                require $module;
                1;
            } or do {
                $self->{logger}->warn("Failed to load ${module}: $@. Make sure you're not missing a packlist as a result!");
                next;
            };
            push @loadable, $module;
        }
        my @pack_dirs = uniq(
            grep { -d $_ }
            map { catdir($_, 'auto') } @INC
        );
        # Keys of that hash are all paths listed in packlists while values
        # are paths to packlist file containing key as line.
        my %pack_reverse_internals;
        find({
            no_chdir => 1,
            wanted => sub {
                return unless m![\\/]\.packlist$! && -f $_;
                $pack_reverse_internals{$_} = $File::Find::name for lines_of($File::Find::name);
            },
        }, @pack_dirs);
        # Keys of that hash are files listed in packlists responsible for our
        # dependencies. So if packlist file contains loadable module, every file
        # in that packlist will be the key of %found hash. Value is module file
        # with OS-specific file notation (delimiters and '.pm' extension).
        my %found;
        @found{map { $pack_reverse_internals{Cwd::abs_path($INC{$_})} || "" } @loadable} = @loadable;
        delete $found{""};
        $self->{logger}->info(">>>>> loadable");
        $self->{logger}->info($_) for @loadable;
        $self->{logger}->info(">>>>> orphans loadable");
        $self->{logger}->info($_) for grep { not defined $pack_reverse_internals{Cwd::abs_path($INC{$_})} } @loadable;
        $self->{logger}->info(">>>>> packlists");
        $self->{logger}->info($_) for keys %found;
        $self->{logger}->info(">>>>> modules with packlists");
        $self->{logger}->info(module_notation_conv($_)) for values %found;
        $pipe->writer();
        $pipe->autoflush(1);
        store_fd({
                packlists => \%found,
                orphaned => [ grep { not defined $pack_reverse_internals{Cwd::abs_path($INC{$_})} } @loadable ],
            }, $pipe);
        exit 0;
    }
}

sub packlists_to_tree {
    my ($self, $where, $packlists, $modules) = @_;
    if (not $self->{use_cache}) {
        remove_tree $where;
        make_path $where;
    }

    for my $plist (@$packlists) {
        my ($volume, $dir_path, $file) = splitpath $plist;
        my @dirs_path = splitdir $dir_path;
        my $pack_base;

        for my $n (0 .. $#dirs_path) {
            if ($dirs_path[$n] eq 'auto') {
                # $p-2 normally since it's <wanted path>/$Config{archname}/auto but
                # if the last bit is a number it's $Config{archname}/$version/auto
                # so use $p-3 in that case
                my $version_lib = 0+!!( $dirs_path[$n - 1] =~ /^[0-9.]+$/ );
                $pack_base = catpath(
                    $volume,
                    catdir @dirs_path[0 .. $n - (2 + $version_lib)]
                );
                last;
            }
        }

        die "Couldn't find base path of packlist ${plist}\n" unless $pack_base;

        for my $source ( lines_of($plist) ) {
            next unless substr($source, 0, length $pack_base) eq $pack_base;
            my $target = rel2abs(abs2rel($source, $pack_base), $where);
            my $target_dir = catpath( (splitpath $target)[0,1] );
            make_path $target_dir;
            $self->{logger}->info("Copying $source to $target");
            copy $source => $target;
        }
    }
}

sub fatpack_file {
    my ($self, $filename) = @_;
    my $shebang;
    my $script_code;

    if (defined $filename and -r $filename) {
        ($shebang, $script_code) = $self->load_main_script($filename);
    }

    my @dirs = $self->fatpack_collect_dirs();
}

sub fatpack_collect_dirs {
    my ($self) = @_;
    return grep -d, map { rel2abs $_, cwd } ($self->{fatlib_dir}, $self->{proj_dir});
}

sub lines_of {
    map +(chomp,$_)[1], do { local @ARGV = ($_[0]); <> };
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
        if ($args{direction} eq 'to_dotted' or
            $args{direction} eq 'to_fname'      )
        {
            $direction = $args{direction} eq 'to_dotted' ? 1 : 0;
        }
        else
        {
            return;
        }
    }
    my $base = (exists $args{base} and not $args{base} eq "")
        ? $args{base}
        : $INC[0];

    my %separators = (  MSWin32 => '\\',
                        Unix    => '/'  );
    my $path_separator = $separators{$^O} || $separators{Unix};

    if ($direction) {
        my $mod_path = $namestring;
        if (index $namestring, $path_separator) {
            $mod_path = abs2rel $namestring, $base;
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

sub run {
    my ($self) = @_;
    my @non_core_deps = (
        $self->trace_noncore_dependencies(to_packlist => 1),
        @{$self->{non_CORE}}
    );
    $self->add_forced_core_dependenceies(\@non_core_deps);
    my @non_proj_deps = $self->filter_non_proj_modules(\@non_core_deps);
    @{$self->{xsed_deps}} = $self->filter_xs_modules(\@non_proj_deps);

    $self->{logger}->info("--- non-core-deps");
    $self->{logger}->info($_) for (@non_core_deps);
    $self->{logger}->info("--- non-proj-deps");
    $self->{logger}->info($_) for (@non_proj_deps);
    $self->{logger}->info("--- xsed-deps");
    $self->{logger}->info($_) for (@{$self->{xsed_deps}});

    # $self->add_noncore_dependenceies
    my @packlists = $self->packlist(\@non_proj_deps);

    $self->{logger}->info("--- packlists");
    $self->{logger}->info($_) for (@packlists);

    make_path $self->{fatlib_dir};

    $self->{logger}->info("Fatlib directory: $self->{fatlib_dir}");

    my $base = $self->{fatlib_dir};
    $self->packlists_to_tree($base, \@packlists);
}

sub build_dir {
    my ($self, @dirs) = @_;
    my @dir;
    for my $d (grep -d, @dirs) {
        my $try = catdir($d, "lib/perl5");
        if (-d $try) {
            push @dir, $try, catdir($try, $Config{archname});
        } else {
            push @dir, $d, catdir($d, $Config{archname});
        }
    }
    return [ grep -d, @dir ];
}

# Logging subroutine of App::FatPacker::Script object.
# Usage:
#    $obj->log(MSG, [ [ LEVEL ],
#       [ msgs => ADD_MSG | [ ADD_MSG_1, ADD_MSG_2, ...] | ADD_MSG_ARY_REF ],
#       [ attrs => ATTR_STR | [ ATTR_STR_1, ATTR_STR_2, ... ] | ATTR_STR_ARY_REF ],
#       [ tabs => INT ],
#       [ colored => 0|1 ] ]);

1;
__END__

=encoding utf-8

=head1 NAME

App::FatPacker::Script — пашол на хуй

=head1 SYNOPSIS

    > fatpack-script script.pl

=cut
