package App::FatPacker::Script::Core;

use strict;
use warnings;
use 5.010001;

use Carp ();
use Log::Any ();

use List::Util qw/uniq/; 

use Cwd ();
use File::Spec::Functions qw/
    rel2abs
    /;

use App::FatPacker::Script::Utils;
use App::FatPacker::Script::Filters ();

# sub AUTOCAN {
#     my ($self, $method) = @_;
#     if ($method =~ m/^filter_\w*/) {
#         for my $f (@{$self->{filters}}) {
#             if ($f->can($method)) {
#                 return \&{$self->$f->$method};
#             }
#         }
#     }
#     return undef;
# }

sub AUTOLOAD {
    my ($inv) = @_;
    my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
    unless ( defined $inv
        && (!ref $inv or Scalar::Util::blessed $inv)
        && $inv->isa(__PACKAGE__) )
    {
        Carp::croak "Undefined subroutine &${package}::$method called"
    }
    return if $method eq 'DESTROY';
    
    my $sub = undef;
    if ($method =~ m/^filter_(.+)*/) {
        for my $f (@{$inv->{_filters}}) {
            if ($f->can($method)) {
                $sub = $f->can($method);
            }
        }
    }

    unless ( defined $sub and do { local $@; eval { $sub = \&$sub; 1 } } ) {
        Carp::croak qq[Can't locate object method "$method"] .
                    qq[via package "$package"]
    }
    # allow overloads and blessed subrefs; assign ref so overload is only invoked once
    {
        require Sub::Util;
        no strict 'refs';
        *{"${package}::$method"} = Sub::Util::set_subname("${package}::$method", $sub);
    }
    goto &$sub;
}

sub can {
    my ($package, $method) = @_;
    my $sub = $package->SUPER::can($method);
    return $sub if defined $sub;

    if ($method =~ m/^filter_(.+)$/) {
        for my $f (@{$package->{_filters}}) {
            if ($f->can($method)) {
                $sub = $f->can($method);
            }
        }
    }

    unless ( defined $sub and do { local $@; eval { $sub = \&$sub; 1 } } ) {
        return undef;
    }
    # allow overloads and blessed subrefs; assign ref so overload is only invoked once
    {
        require Sub::Util;
        no strict 'refs';
        *{"${package}::$method"} = Sub::Util::set_subname("${package}::$method", $sub);
    }
    return $sub;
}

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless {}, $class;

    $self->_defaultize();
    $self->_initialize(%params);    

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
    $self->{target_version} = $^V;

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
            ['targer_version', 'target_Perl_version'],
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

    foreach my $dirs_pair (
            ['dir', 'module_dirs'],
            ['proj_dir', 'proj_dirs'],
        )
    {
        $self->{$dirs_pair->[0]} = exists $params{$dirs_pair->[1]}
            ? [ map { rel2abs($_, Cwd::cwd()) } @{$params{$dirs_pair->[1]}} ]
            : $self->{$dirs_pair->[0]};                
    }

    foreach my $dir_pair (
            ['output_file', 'output'],
            ['fatlib_dir', 'fatlib_dir'],
        )
    {
        $self->{$dir_pair->[0]} = exists $params{$dir_pair->[1]}
            ? rel2abs($params{$dir_pair->[1]}, Cwd::cwd())
            : $self->{$dir_pair->[0]};
    }

    $self->{script} = $params{script} || Carp::croak("Missing script");

    $self->{_logger} = Log::Any->get_logger();

    $self->{_filters} = [ App::FatPacker::Script::Filters->new(core_obj => $self) ];

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
            not Module::CoreList->is_core($_, undef, $self->{target});
        }
        sort {
            $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger;
        }
        map {
            chomp($_);
            module_notation_conv($_, direction => 'to_dotted', relative => 0);
        } qx/$^X @opts/;                                            ## no critic

    if (wantarray()) {
        return @non_core;
    } 
    $self->{_non_core_deps} = \@non_core;
    if (defined wantarray()) {
        return $self;
    } else {
        return;
    }
}

sub add_forced_core_dependenceies {
    my ($self, $noncore) = @_;

    if (not defined $noncore) {
        $noncore = $self->{_non_core_deps};
    }

    # Check whether added
    foreach my $forced_core (@{$self->{forced_CORE_modules}}) {
        if (Module::CoreList->is_core($forced_core, undef, $self->{target})) {
            push @$noncore, $forced_core;
        }
    }
    if (wantarray()) {
        return (sort {
                $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger
            } @$noncore);
    } elsif (defined wantarray()) {
        return $self;
    } else {
        return;
    }
}

1;