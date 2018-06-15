package App::FatPacker::Script::Filters;

use strict;
use warnings;
use 5.010001;

use Scalar::Util ();

use Carp (); 
use Log::Any ();

use IO::Pipe;
use Storable qw/fd_retrieve store_fd/;

use File::Spec::Functions qw/catfile/;

use App::FatPacker::Script::Utils qw/
        still_core module_notation_conv
    /;

sub new {
    my $class = shift;
    my %params = @_;
    my $self = bless {}, $class;

    $self->_initialize(%params);

    return $self;
}

sub _initialize {
    my $self = shift;
    my %params = @_;

    $self->{core_obj} = $params{core_obj} || Carp::croak("Missing core object");
    Scalar::Util::weaken($self->{core_obj});

    $self->{_logger} = Log::Any->get_logger();
}

sub filter_noncore_dependencies {
    my ($self, $deps) = @_;
    my $core_obj = $self->{core_obj};

    $deps = defined $deps ? $deps : $core_obj->{non_CORE_modules};

    my @non_core = grep { 
            not still_core($_, $core_obj->{target_Perl_version})
        } @$deps;

    if (wantarray()) {
        return @non_core;
    } else {
        push @{$core_obj->{_non_core_deps}}, @non_core;
        return $core_obj;
    }
}

sub filter_non_proj_modules {
    my ($self, $modules) = @_;
    my $core_obj = $self->{core_obj};

    $modules = defined $modules ? $modules : $core_obj->{_non_core_deps};

    my $pipe = IO::Pipe->new();
    my $pid = fork;
    defined($pid) or die "Can't fork for filtering project modules: $!\n";

    if ($pid) {
        $pipe->reader();
        my %non_proj_or_cached = %{ fd_retrieve($pipe) };
        
        if (wantarray()) {
            return %non_proj_or_cached;
        } else {
            $core_obj->{_non_proj_or_cached} = \%non_proj_or_cached;
            return $core_obj;
        }
    } else {
        local @INC = $core_obj->inc_dirs();
        my %non_proj_or_cached;
        for my $non_core (@$modules) {
            my $mod_fname = module_notation_conv($non_core,
                direction => 'to_fname');
            eval {
                require $mod_fname; 
                1;
            } or do {
                $self->{_logger}->warn("Cannot load $non_core module: $@");
                next;
            };
            # If use-cache options was set, we consider fatlib directory as part
            # of project directory so all modules cached by previous executions 
            # of script will be considered as project modules
            my @proj_dir = ($core_obj->{use_cache})
                ? ($core_obj->{fatlib_dir}, @{$core_obj->{proj_dir}})
                : @{$core_obj->{proj_dir}};
            if (not grep {$INC{$mod_fname} =~ catfile($_, $mod_fname)} @proj_dir)
            {
                push @{$non_proj_or_cached{non_proj}}, $non_core;
            }
            if ($core_obj->{use_cache}) {
                if ( $INC{$mod_fname} =~ catfile($core_obj->{fatlib_dir}, $mod_fname) )
                {
                    push @{$non_proj_or_cached{cached}}, $non_core;
                }
            }
        }
        $pipe->writer();
        $pipe->autoflush(1);
        store_fd({ %non_proj_or_cached }, $pipe);
        exit 0;
    }
}

sub filter_xs_modules {
    my ($self, $modules) = @_;
    my $core_obj = $self->{core_obj};

    $modules = defined $modules ? $modules : $core_obj->{_non_proj_or_cached}->{non_proj};

    my $pipe = IO::Pipe->new();
    my $pid = fork;
    defined($pid) or die "Can't fork for filtering XS modules: $!\n";

    if ($pid) {
        $pipe->reader();
        my @xsed_modules = @{ fd_retrieve($pipe) };
        
        if (wantarray()) {
            return @xsed_modules;
        } else {
            $core_obj->{_xsed} = \@xsed_modules;
            return $core_obj;
        }
    } else {
        local @INC = $core_obj->inc_dirs(proj_dir => 0);
        use DynaLoader;
        my @xsed_modules;
        for my $module (@$modules) {
            my $module_fname = 
                module_notation_conv($module, direction => 'to_fname');
            eval {
                require $module_fname;
                1;
            } or do {
                $self->{_logger}->warn("Failed to load ${module_fname}: $@");
            };
            if ( grep { $module_fname eq $_ } @DynaLoader::dl_modules ) {
                push @xsed_modules, $module;
            }
        }
        $pipe->writer();
        $pipe->autoflush(1);
        store_fd(\@xsed_modules, $pipe);
        exit 0;
    }
}

1;