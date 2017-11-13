package App::FatPacker::Script;

use strict;
use warnings;
use 5.010;

use Config;
use version;

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;

use File::Find qw/find/;
use File::Spec::Functions qw/catdir/;
use Perl::Strip;
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
        "i|includes=s@" => \(my $additional_modules = []),
        "h|help"        => sub { pod2usage(1) },
        "o|output=s"    => \(my $output),
        "q|quiet"       => \(my $quiet),
        "s|strict"      => \(my $strict),
        "v|version"     => sub { printf "%s %s\n", __PACKAGE__, __PACKAGE__->VERSION; exit },
        "t|target=s"    => $version_handler,
        "color!"        => \(my $color = 1),
        "shebang=s"     => \(my $custom_shebang),
        "exclude-strip=s@" => \(my $exclude_strip),
        "no-strip|no-perl-strip" => \(my $no_perl_strip),
    or pod2usage(2);

    $self->{script}     = shift @ARGV or do { warn "Missing scirpt.\n"; pod2usage(2) };
    push @{$self->{dir}}, split( /,/, join(',', @dirs) );
    $self->{forced_CORE} = $additional_modules;
    $self->{output}     = $output;
    $self->{quiet}      = $quiet;
    $self->{strict}     = $strict;
    $self->{color}      = $color;
    $self->{target}     = $target_version;
    $self->{perl_strip} = $no_perl_strip ? undef : Perl::Strip->new;
    $self->{custom_shebang} = $custom_shebang;
    $self->{exclude_strip}  = [map { qr/$_/ } @{$exclude_strip || []}];
    $self->{exclude}    = [];

    return $self;
}

sub trace_noncore_dependencies {
    my ($self, %args) = @_;

    my @opts = ($self->{script});
    push @opts, '2>/dev/null' if ($self->{quiet});
    my $trace_opts = '>&STDOUT';

    local $ENV{PERL5OPT} = join ' ',
    ( $ENV{PERL5OPT} || () ), '-MApp::FatPacker::Trace=' . $trace_opts;

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

sub add_core_dependenceies {
    my ($self, @noncore) = @_;
    push @noncore, @{$self->{forced_CORE}};
    return (sort { $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger } @noncore);
}

sub packlist {
    my ($self, @deps) = @_;
    foreach my $pl ($self->packlists_containing(@deps)) {
        print "${pl}\n";
    }
}

sub packlists_containing {
    my ($self, @targets) = @_;
    my @targetss;
    {
        local @INC = ('lib', @INC);
        foreach my $t (@targets) {
            unless (eval { require $t; 1}) {
                warn "Failed to load ${t}: $@\n"
                ."Make sure you're not missing a packlist as a result\n";
                next;
            }
            push @targetss, $t;
        }
    }
    my @search = grep -d $_, map catdir($_, 'auto'), @INC;
    my %pack_rev;
    find({
        no_chdir => 1,
        wanted => sub {
            return unless /[\\\/]\.packlist$/ && -f $_;
            $pack_rev{$_} = $File::Find::name for $self->lines_of($File::Find::name);
        },
    }, @search);
    my %found; @found{map +($pack_rev{Cwd::abs_path($INC{$_})}||()), @targetss} = ();
    sort keys %found;
}

sub lines_of {
    map +(chomp,$_)[1], do { local @ARGV = ($_[1]); <> };
}

sub run {
    my ($self) = @_;
    my @deps = $self->add_core_dependenceies($self->trace_noncore_dependencies(to_packlist => 1));
    $self->packlist(@deps);
    say $?;
    use Data::Printer; p @deps;
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
