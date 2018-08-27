package App::FatPacker::Script::Core;

use strict;
use warnings;
use 5.010001;

use Carp qw/croak carp/;
use Log::Any ();

use List::Util qw/uniq/; 

use Cwd ();
use File::Spec::Functions qw/
        catdir
        rel2abs
    /;

use App::FatPacker::Script::Utils;
use App::FatPacker::Script::Filters ();

sub AUTOLOAD {
    my ($inv) = @_;
    my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
    unless ( defined $inv
        && (!ref $inv or Scalar::Util::blessed $inv)
        && $inv->isa(__PACKAGE__) )
    {
        croak "Undefined subroutine &${package}::$method called"
    }
    return if $method eq 'DESTROY';

    my $sub = undef;
    my $filter_obj = undef;
    if ($method =~ m/^filter_(.+)*/) {
        for my $f (@{$inv->{_filters}}) {
            if ($f->can($method)) {
                $sub = $f->can($method);
                $filter_obj = $f;
            }
        }
    }
    unless ( defined $sub and do { local $@; eval { $sub = \&$sub; 1 } } ) {
        croak qq[Can't locate object method "$method"] .
                    qq[via package "$package"]
    }
    # allow overloads and blessed subrefs; assign ref so overload is only invoked once
    {
        no strict 'refs'; ## no critic
        # *{"${package}::$method"} = Sub::Util::set_subname("${package}::$method", $sub);
        *{"${package}::$method"} = sub {
            my $self = shift;
            return $filter_obj->$method(@_);
        }
    }
    my $result_sub = "${package}::$method";
    goto &$result_sub;
}

sub can {
    my ($package, $method) = @_;
    my $sub = $package->SUPER::can($method);
    return $sub if defined $sub;

    my $filter_obj = undef;
    if ($method =~ m/^filter_(.+)$/) {
        for my $f (@{$package->{_filters}}) {
            if ($f->can($method)) {
                $sub = $f->can($method);
                $filter_obj = $f;
            }
        }
    }

    unless ( defined $sub and do { local $@; eval { $sub = \&$sub; 1 } } ) {
        return undef; ## no critic
    }
    # allow overloads and blessed subrefs; assign ref so overload is only invoked once
    {
        require Sub::Util;
        no strict 'refs'; ## no critic
        *{"${package}::$method"} = sub {
            my $self = shift;
            return $filter_obj->$method(@_);
        }
    }
    my $result_sub = "${package}::$method";
    return $result_sub;
}

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless {}, $class;

    $self->_defaultize();
    eval {
        $self->_initialize(%params);
    } or do {
        $self
    }

    return $self;
}

sub _defaultize {
    my $self = shift;
    $self->{output_file} = rel2abs("fatpacked.pl");

    $self->{dir} = [];
    $self->{proj_dir} = [];
    $self->{fatlib_dir} = rel2abs("fatlib");
    $self->{use_cache} = 0;

    $self->{forced_CORE_modules} = [];
    $self->{non_CORE_modules} = [];
    $self->{target_Perl_version} = $^V;

    $self->{strict} = 0;
    $self->{custom_shebang} = undef;
    $self->{perl_strip} = undef;
    $self->{exclude_strip} = [];
}

sub _initialize {
    my $self = shift;
    my %params = @_;

    foreach my $pair (
            ['use_cache', 'use_cache'],
            ['forced_CORE_modules', 'modules', 'forced_CORE'],
            ['non_CORE_modules', 'modules', 'non_CORE'],
            ['target_Perl_version', 'target_Perl_version'],
            ['strict', 'strict'],
            ['custom_shebang', 'custom_shebang'],
            ['perl_strip', 'perl_strip'],
            ['exclude_strip', 'exclude_strip']
        )
    {
        if (scalar(@{$pair}) == 2) {
            $self->{$pair->[0]} = exists $params{$pair->[1]}
                ? $params{$pair->[1]} : $self->{$pair->[0]};
        }
        elsif (scalar(@{$pair}) == 3) {
            $self->{$pair->[0]} = exists $params{$pair->[1]}{$pair->[2]}
                ? $params{$pair->[1]}{$pair->[2]} : $self->{$pair->[0]};
        }
    }

    $self->{dir} = exists $params{module_dirs}
        ? [ map { rel2abs($_) } @{$params{module_dirs}} ]
        : $self->{dir};

    # Concatenate 'lib' to path if and only if directory isn't absolute
    $self->{proj_dir} = exists $params{proj_dirs}
        ? [ map {
                    rel2abs($_) eq $_ ? $_ : catdir(rel2abs($_), "lib")
                } @{$params{proj_dirs}} ]
        : $self->{proj_dir}; 

    foreach my $dir_pair (
            ['output_file', 'output'],
            ['fatlib_dir', 'fatlib_dir'],
        )
    {
        $self->{$dir_pair->[0]} = exists $params{$dir_pair->[1]}
            ? rel2abs($params{$dir_pair->[1]})
            : $self->{$dir_pair->[0]};
    }

    $self->{script} = $params{script} || croak("Missing script");

    $self->{_logger} = Log::Any->get_logger();

    $self->{_filters} = [
        App::FatPacker::Script::Filters->new(core_obj => $self)
    ];

    $self->{_non_core_deps} = [];
    $self->{_non_proj_or_cached} = {};
    $self->{_xsed} = [];
}

sub load_filters {
    my ($self, @filter_classes) = @_;

    for my $f (@filter_classes) {
        $f = module_notation_conv($f, direction => 'to_fname');
        eval {
            require $f;
            push @{$self->{_filters}}, $f->new(core_obj => $self);
        } or do {
            $self->{_logger}->error("Can't load filter module $f");
        }
    }

    @{$self->{_filters}} = uniq @{$self->{_filters}};
}

sub inc_dirs {
    my $self = shift;
    my %params = @_;
    $params{proj_dir} = exists $params{proj_dir} ? $params{proj_dir} : 1;

    return uniq (
        ( $params{proj_dir} ? @{$self->{proj_dir}} : () ),
        ( $self->{use_cache} ? $self->{fatlib_dir} : () ),
        @{$self->{dir}}, 
        @INC
    );
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
        @{$self->{proj_dir}},
        ( $self->{use_cache} ? $self->{fatlib_dir} : () ),
        @{$self->{dir}},
        ( $ENV{PERL5LIB} || () );

    my @non_core =
        map { 
            $args{to_packlist}
                ? module_notation_conv($_, direction => 'to_fname')
                : $_;
        }
        grep {
            not still_core($_, $self->{target_Perl_version});
        }
        sort {
            $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger;
        }
        map {
            my $module = $_;
            chomp($module);
            module_notation_conv($module, direction => 'to_dotted', 
                                 relative => 0);
        } qx/$^X @opts/;                                            ## no critic

    if (wantarray()) {
        return @non_core;
    } else {
        $self->{_non_core_deps} = \@non_core;
        return $self;
    }
}

sub add_forced_core_dependencies {
    my ($self, $noncore) = @_;

    if (not defined $noncore) {
        $noncore = $self->{_non_core_deps};
    }

    # Check whether added
    foreach my $forced_core (@{$self->{forced_CORE_modules}}) {
        if (Module::CoreList->is_core($forced_core, undef,
                                      $self->{target_Perl_version}->numify())) {
            push @$noncore, $forced_core;
        }
    }
    if (wantarray()) {
        return (sort {
                $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger
            } @$noncore);
    } else {
        return $self;
    }
}

1;
