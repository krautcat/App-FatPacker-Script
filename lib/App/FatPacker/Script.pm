package App::FatPacker::Script;
# ABSTRACT: FatPacker for scripts
use strict;
use warnings;
use 5.010001;

use Config;
use version;
use List::Util qw/uniq/;

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;

use Cwd qw/cwd/;
use File::Find qw/find/;
use File::Copy qw/copy/;
use File::Path qw/make_path remove_tree/;
use File::Spec::Functions qw/
    catdir catpath
    splitdir splitpath
    rel2abs abs2rel
    /;
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

    # Default values
    my @dirs = ("lib", "fatlib", "local", "extlib");
    my (@additional_core, @non_core) = (() , ());
    my $target_version = $];

    # Check, if passed version exists or not
    my $version_handler = sub {
        my $target = version->parse($_[1] || $target_version)->numify;
        $target_version = exists $Module::CoreList::version{$target}
            ? $target
            : $target_version;
    };

    GetOptions
        "d|dir=s@"      => \@dirs,
        "i|includes=s@" => \@additional_core,
        "n|non-core=s@" => \@non_core,
        "h|help"        => sub { pod2usage(1) },
        "o|output=s"    => \(my $output),
        "q|quiet"       => \(my $quiet),
        "s|strict"      => \(my $strict),
        "v|version"     => sub { printf "%s %s\n", __PACKAGE__, __PACKAGE__->VERSION; exit },
        "t|target=s"    => $version_handler,
        "color!"        => \(my $color = 1),
        "fatlib-dir=s"  => \(my $fatlib_dir = "fatlib"),
        "shebang=s"     => \(my $custom_shebang),
        "exclude-strip=s@" => \(my $exclude_strip),
        "no-strip|no-perl-strip" => \(my $no_perl_strip),
    or pod2usage(2);

    $self->{script}     = shift @ARGV or do { warn "Missing scirpt.\n"; pod2usage(2) };
    push @{$self->{dir}}, map { $_ = rel2abs $_ }
                          split( /,/, join(',', @dirs) );
    push @{$self->{forced_CORE}}, split( /,/, join(',', @additional_core) );
    push @{$self->{non_CORE}}, split( /,/, join(',', @non_core) );
    $self->{output}     = $output;
    $self->{quiet}      = $quiet;
    $self->{strict}     = $strict;
    $self->{color}      = $color;
    $self->{target}     = $target_version;
    $self->{perl_strip} = $no_perl_strip ? undef : Perl::Strip->new;
    $self->{custom_shebang} = $custom_shebang;
    $self->{exclude_strip}  = [map { qr/$_/ } @{$exclude_strip || []}];
    $self->{exclude}    = [];
    $self->{fatlib_dir} = rel2abs $fatlib_dir;

    return $self;
}

sub trace_noncore_dependencies {
    my ($self, %args) = @_;

    my @opts = ($self->{script});
    push @opts, '2>/dev/null' if ($self->{quiet});
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
                warn "Cannot load $non_core module: $@\n";
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
                warn "Failed to load ${module_file}: $@\n";
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
    return ($self->packlists_containing($deps));
}

sub packlists_containing {
    my ($self, $module_files) = @_;
    my @packlists;

    my $pid = open(my $pipe_packa, "-|");
    defined($pid) or die "Can't fork for loading modules: $!\n";

    if ($pid) {
        @packlists = (<$pipe_packa>);
        chomp @packlists;
        return @packlists;
    } else {
        local @INC = (@{$self->{dir}}, @INC);
        my @loadable = ();
        for my $module (@$module_files) {
            eval {
                require $module; 
                1;
            } or do {
                warn "Failed to load ${module}: $@"
                    . "Make sure you're not missing a packlist as a result!\n";
                next;
            };
            push @loadable, $module;
        }
        my @pack_dirs = uniq(
            grep { -d $_ }
            map { catdir($_, 'auto') } @INC
        );
        my %pack_rev;
        find({
            no_chdir => 1,
            wanted => sub {
                return unless m![\\/]\.packlist$! && -f $_;
                $pack_rev{$_} = $File::Find::name for lines_of($File::Find::name);
            },
        }, @pack_dirs);
        my %found;
        @found{map { $pack_rev{Cwd::abs_path($INC{$_})} || "" } @loadable} = ();
        say for sort keys %found;
        exit 0;
    }
}

sub packlists_to_tree {
    my ($self, $where, $packlists) = @_;
    remove_tree $where;
    make_path $where;

    for my $plist (@$packlists) {
        my ($volume, $dir_path, $file) = splitpath $plist;
        my @dirs_path = splitdir $dir_path;
        my $pack_base;

        for my $n (0 .. $#dirs_path) {
            if ($dirs_path[$n] eq 'auto') {
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
            copy $source => $target;
        }
    }
}

sub lines_of {
    map +(chomp,$_)[1], do { local @ARGV = ($_[0]); <> };
}

sub run {
    my ($self) = @_;
    my @non_core_deps = (
        $self->trace_noncore_dependencies(to_packlist => 1), 
        @{$self->{non_CORE}}
    );
    $self->add_forced_core_dependenceies(\@non_core_deps);
    my @non_proj_deps = $self->filter_non_proj_modules(\@non_core_deps);
    my @xsed_deps = $self->filter_xs_modules(\@non_proj_deps);
    say "--- non-core-deps";
    say for (@non_core_deps);
    say "--- non-proj-deps";
    say for (@non_proj_deps);
    say "--- xsed-deps";
    say for (@xsed_deps);

    # $self->add_noncore_dependenceies
    my @packlists = $self->packlist(\@non_proj_deps);
    say "--- packlists";
    say for (@packlists);

    make_path('fatlib');
    say $self->{fatlib_dir};
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

1;
__END__

=encoding utf-8

=head1 NAME

App::FatPacker::Script — пашол на хуй

=head1 SYNOPSIS

    > fatpack-script script.pl

=cut
