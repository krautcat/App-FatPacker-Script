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
    catdir catpath catfile
    splitdir splitpath
    rel2abs abs2rel
    file_name_is_absolute
    /;

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;

use Log::Any;
use Log::Any::Adapter;

use Perl::Strip;
use B qw/perlstring/;
use Module::CoreList;
use App::FatPacker;
use App::FatPacker::Script::Core;
use App::FatPacker::Script::Utils;

our $VERSION = '0.01';

our $IGNORE_FILE = [
    qr/\.pod$/,
    qr/\.packlist$/,
    qr/MYMETA\.json$/,
    qr/install\.json$/,
];

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @_;

    Getopt::Long::Configure("bundling");

    # Default values
    my @dirs = ("local", "extlib");
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

    my $version_sub = sub {
        printf "%s %s\n", __PACKAGE__, __PACKAGE__->VERSION; exit 
    };

    GetOptions
        "b|base=s"      => \(my $base = cwd()),
        
        "d|dir=s@"      => \@dirs,
        "use-cache!"    => \(my $cache = 1),
        "f|fatlib-dir=s"
                        => \(my $fatlib_dir = "fatlib"),
        "p|proj-dir=s@" => \@proj_dirs,
        
        "i|includes=s@" => \@additional_core,
        "n|non-core=s@" => \@non_core,
        
        "to=s"          => \(my $result_file = "fatpacked.pl"),
        
        "o|output=s"    => \(my $output),
        "q|quiet+"      => \(my $quiet = 0),
        "v|verbose+"    => \(my $verbose = 0),
        "color!"        => \(my $color = 1),
        
        "t|target=s"    => $version_handler,
        "shebang=s"     => \(my $custom_shebang),
        "s|strict"      => \(my $strict),
        "exclude-strip=s@" => \(my $exclude_strip),
        "no-strip|no-perl-strip" => \(my $no_perl_strip),
        
        "V|version"     => $version_sub,
        "h|help"        => sub { pod2usage(1) },
        
        or pod2usage(2);

    my $script = shift @ARGV or do { 
        warn "Missing scirpt.\n"; pod2usage(2)
    };
    
    # Directories to search module files, local directories 
    @dirs = map { rel2abs $_, $base }
                split( /,/, join(',', @dirs) );
    # Use lib directory in base directory if project directory wasn't supplied
    # via command line arguments
    @proj_dirs = scalar @proj_dirs
        ? ( map { rel2abs $_, $base }
            split( /,/, join(',', @proj_dirs) ) )
        : ( rel2abs "lib", $base );
    $fatlib_dir = rel2abs $fatlib_dir, $base;
    # Add fatlib directory if use cache
    if ($cache) {
        unshift @dirs, $fatlib_dir;
    }
    # Concatenate project directories at the beginning of array of directories
    # to look up modules and then remove duplicates
    unshift @dirs, @proj_dirs;
    @dirs = uniq @dirs;

    $self->{core_obj} = App::FatPacker::Script::Core->new(
            script      =>  $script,
            output      =>  rel2abs($result_file, $base),

            module_dirs =>  \@dirs,
            proj_dirs   =>  \@proj_dirs,
            fatlib_dir  =>  $fatlib_dir,
            use_cache   =>  $cache,
            
            modules => {
                forced_CORE =>  [ split( /,/, join(',', @additional_core) ) ],
                non_CORE    =>  [ split( /,/, join(',', @non_core) ) ],
            },
            target_Perl_version => $target_version,

            strict      =>  $strict,
            custom_shebang  =>  $custom_shebang,
            perl_strip      =>  $no_perl_strip ? undef : Perl::Strip->new(),
            exclude_strip   =>  [ map { qr/$_/ } @{$exclude_strip || []} ],
        );

    # Setting output descriptor. Try to open file supplied from command line.
    # options. If opening failed, show message to user and return to fallback
    # default mode (logging to STDERR).
    my $verboseness = $verbose - $quiet;
    if (defined $output and $output ne '') {
        eval {
            Log::Any::Adapter->set(
                '+App::FatPacker::Script::Log::Adapter::File',
                rel2abs($output, $base),
                log_level => $verboseness,
                timestamp => 1);
        } or do {
            my $msg = "Can't open $output for logging! Reason: $@";
            if ( is_interactive(\*STDERR) ) {
                $msg = colored $msg, 'bright_red';
            }
            warn $msg;
            Log::Any::Adapter->set(
                '+App::FatPacker::Script::Log::Adapter::Interactive',
                log_level => $verboseness,
                colored => $color);
        }
    } else {
        Log::Any::Adapter->set(
            '+App::FatPacker::Script::Log::Adapter::Interactive',
            log_level => $verboseness,
            colored => $color,
            indentation => { info => 0 },
            colors => { notice => 'white' });
    }
    
    $self->{logger} = Log::Any->get_logger();
    $self->{verboseness} = $verboseness;

    return $self;
}

### Packlisting subroutines

sub packlist {
    my ($self, $deps) = @_;
    my %h = $self->packlists_containing($deps);
    $self->{logger}->info(">>>>> non-XS orphans");
    $self->{logger}->info($_) for grep {
            my $m = $_;
            not grep {
                    $_ eq $m 
                } @{$self->{xsed_deps}}
        } @{$h{orphaned}};
    $self->{logger}->info(">>>>> XS orphans");
    $self->{logger}->info($_) for grep {
            my $m = $_;
            grep { 
                    $_ eq $m 
                } @{$self->{xsed_deps}}
        } @{$h{orphaned}};
    return ( keys %{$h{packlists}} );
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
        local @INC = (
            exclude_ary($self->{core_obj}->{dir}, [@{$self->{core_obj}->{proj_dir}}, $self->{core_obj}->{fatlib_dir}]),
            @INC
        );
        my @loadable = ();
        for my $module (@$module_files) {
            eval {
                require $module;
                1;
            } or do {
                $self->{logger}->warn("Failed to load ${module}: $@. "
                    ."Make sure you're not missing a packlist as a result!");
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
                foreach my $line (lines_of($File::Find::name)) {
                    $pack_reverse_internals{$line} = $File::Find::name
                }
            },
        }, @pack_dirs);
        # Keys of that hash are files listed in packlists responsible for our
        # dependencies. So if packlist file contains loadable module, every file
        # in that packlist will be the key of %found hash. Value is module file
        # with OS-specific file notation (delimiters and '.pm' extension).
        my %found;
        @found{map { 
                $pack_reverse_internals{rel2abs($INC{$_}, $self->{core_obj}->{base})} || "" 
            } @loadable} = @loadable;
        delete $found{""};
        $self->{logger}->info(">>>>> loadable");
        $self->{logger}->notice($_) for @loadable;
        $self->{logger}->info(">>>>> orphans loadable");
        $self->{logger}->notice($_) for grep {
                not defined $pack_reverse_internals{
                    rel2abs($INC{$_}, $self->{core_obj}->{base})
                }
            } @loadable;
        $self->{logger}->info(">>>>> packlists");
        $self->{logger}->notice($_) for keys %found;
        $self->{logger}->info(">>>>> modules with packlists");
        $self->{logger}->notice(module_notation_conv($_)) for values %found;
        $pipe->writer();
        $pipe->autoflush(1);
        store_fd({
                packlists => \%found,
                orphaned => [ grep {
                        not defined $pack_reverse_internals{
                            rel2abs($INC{$_}, $self->{core_obj}->{base})
                        }
                    } @loadable ],
            }, $pipe);
        exit 0;
    }
}

sub packlists_to_tree {
    my ($self, $where, $packlists, $modules) = @_;
    if (not $self->{core_obj}->{use_cache}) {
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

### Fatpacking subroutines

sub fatpack_file {
    my ($self) = @_;
    my $shebang;
    my $script_code;

    if (-r $self->{core_obj}->{script}) {
        ($shebang, $script_code) = $self->fatpack_load_main_script($self->{core_obj}->{script});
    }

    my @dirs = $self->fatpack_collect_dirs();
    my %files;
    foreach my $dir (@dirs) {
        $self->fatpack_collect_files($dir, \%files) ;
    }
    use Data::Printer; my @a = keys %files; p @dirs;
    return join "\n", $shebang, $self->fatpack_code(\%files), $script_code;
}

sub fatpack_collect_dirs {
    my ($self) = @_;
    return grep -d, map {
            rel2abs $_, $self->{core_obj}->{base}
        } ($self->{core_obj}->{fatlib_dir}, @{$self->{core_obj}->{proj_dir}});
}

sub fatpack_collect_files {
    my ($self, $dir, $files) = @_;
 
    my $absolute_dir = rel2abs $dir, $self->{core_obj}->{base};
    # When $dir is not an archlib,
    # and we are about to search $dir/archlib, skip it!
    # because $dir/archlib itself will be searched another time.
    my $skip_dir = catdir($absolute_dir, $Config{archname});
    $skip_dir = qr/\Q$skip_dir\E/;
 
    my $find = sub {
        return unless -f $_;
        for my $ignore (@$IGNORE_FILE) {
            if ($_ =~ $ignore) {
                return;
            }
        }
        my $original = $_;
        my $absolute = rel2abs $original, $self->{core_obj}->{base};
        return if $absolute =~ $skip_dir;
        my $relative = File::Spec::Unix->abs2rel($absolute, $absolute_dir);
        if (not $_ =~ /\.(?:pm|ix|al|pl)$/) {
            $self->warning("skip non perl module file $relative");
            return;
        }
        $files->{$relative} = $self->fatpack_load_file($absolute, $relative, $original);
    };
    find({wanted => $find, no_chdir => 1}, $dir);
}

sub fatpack_load_file {
    my ($self, $file) = @_;
    my $content = do {
        local (@ARGV, $/) = ($file);
        <>;
    };
    close ARGV;
    return $content;
}

sub fatpack_load_main_script {
    my ($self, $file) = @_;
    open my $fh, "<", $file or die "Cannot open '$file': $!\n";
    my @lines = <$fh>;
    my @shebang;
    if (@lines && index($lines[0], '#!') == 0) {
        while (1) {
            push @shebang, shift @lines;
            last if $shebang[-1] =~ m{^\#\!.*perl};
        }
    }
    return ((join "", @shebang), (join "", @lines));
}

sub fatpack_start {
    return stripspace <<'    END_START';
        # This chunk of stuff was generated by App::FatPacker. To find the original
        # file's code, look for the end of this BEGIN block or the string 'FATPACK'
        BEGIN {
            my %fatpacked;
    END_START
}
 
sub fatpack_end {
    return stripspace <<'    END_END';
        s/^  //mg for values %fatpacked;
    
        my $class = 'FatPacked::'.(0+\%fatpacked);
        no strict 'refs';
        *{"${class}::files"} = sub { keys %{$_[0]} };
    
        if ($] < 5.008) {
            *{"${class}::INC"} = sub {
                if (my $fat = $_[0]{$_[1]}) {
                    my $pos = 0;
                    my $last = length $fat;
                    return (sub {
                            return 0 if $pos == $last;
                            my $next = (1 + index $fat, "\n", $pos) || $last;
                            $_ .= substr $fat, $pos, $next - $pos;
                            $pos = $next;
                            return 1;
                        });
                }
            };
        }
    
        else {
            *{"${class}::INC"} = sub {
                if (my $fat = $_[0]{$_[1]}) {
                    open my $fh, '<', \$fat
                        or die "FatPacker error loading $_[1] (could be a perl installation issue?)";
                    return $fh;
                }
                return;
            };
        }
    
        unshift @INC, bless \%fatpacked, $class;
    } # END OF FATPACK CODE
    END_END
}
 
sub fatpack_code {
    my ($self, $files) = @_;
    my @segments = map {
            (my $stub = $_) =~ s/\.pm$//;
            my $name = uc join '_', split '/', $stub;
            my $data = $files->{$_};
            $data =~ s/^/  /mg;
            $data =~ s/(?<!\n)\z/\n/;
            '$fatpacked{'
                . perlstring($_)
                . qq!} = '#line '.(1+__LINE__).' "'.__FILE__."\\"\\n".<<'${name}';\n!
                . qq!${data}${name}\n!;
        } sort keys %$files;
    
    return join "\n", $self->fatpack_start, @segments, $self->fatpack_end;
}

sub run {
    my ($self) = @_;

    $self->{core_obj}
    # Tracing non-core dependencies of packing module and adding non-core
    # dependencies supplied from command line
            ->trace_noncore_dependencies(to_packlist => 1)
            ->filter_noncore_dependencies()
    # Adding to the list of non-core dependencies core modules which must be
    # included in list of modules for packing
            ->add_forced_core_dependencies()
    # Filter non-project module dependencies
            ->filter_non_proj_modules()
    # Filter all xs modules
            ->filter_xs_modules();




    $self->{logger}->info("--- non-core-deps");
    $self->{logger}->notice($_) for (@{$self->{core_obj}->{_non_core_deps}});
    $self->{logger}->info("--- non-proj-deps");
    $self->{logger}->notice($_) for (@{$self->{core_obj}->{_non_proj_or_cached}->{non_proj}});
    $self->{logger}->info("--- cached-deps");
    $self->{logger}->notice($_) for (@{$self->{core_obj}->{_non_proj_or_cached}->{cached}});
    $self->{logger}->info("--- xsed-deps");
    $self->{logger}->notice($_) for (@{$self->{core_obj}->{_xsed}});

    # Getting packlists for all non-project dependencies
    my @packlists = $self->packlist($self->{core_obj}->{_non_proj_or_cached}->{non_proj});

    $self->{logger}->info("--- packlists");
    $self->{logger}->notice($_) for (@packlists);

    make_path $self->{core_obj}->{fatlib_dir};

    $self->{logger}->info("Fatlib directory: $self->{core_obj}->{fatlib_dir}");

    # All packlists files move to tree into fatlib directory
    $self->packlists_to_tree($self->{core_obj}->{fatlib_dir}, \@packlists);

    my $fatpacked = $self->fatpack_file();
    my $out_file = IO::File->new($self->{core_obj}->{output_file}, ">");
    die "Cannot open '$self->{result_file}': $!\n" unless defined $out_file;
    print {$out_file} $fatpacked;
    $out_file->close();
    
    my $mode = (stat $self->{core_obj}->{script})[2];
    chmod $mode, $self->{core_obj}->{output_file};
    $self->{logger}->notice("Successfully created $self->{core_obj}->{output_file}");
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

1;
__END__

=encoding utf-8

=head1 NAME

App::FatPacker::Script — пашол на хуй

=head1 SYNOPSIS

    > fatpack-script script.pl

=cut
