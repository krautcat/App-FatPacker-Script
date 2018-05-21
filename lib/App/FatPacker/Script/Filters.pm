package App::FatPacker::Script::Filters;

use strict;
use warnings;
use 5.010001;

use Carp (); 
use Log::Any ();

use IO::Pipe;
use Storable qw/fd_retrieve store_fd/;

use Module::CoreList;

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

    $self->{_logger} = Log::Any->get_logger();
}

sub filter_noncore_dependencies {
    my ($self, $deps) = @_;
    
    $deps = defined $deps ? $deps : $self->{core_obj}->{non_CORE_modules};

    my @non_core = grep {
            not Module::CoreList->is_core($_, undef, 
                $self->{core_obj}->{target_version})
        } @$deps;

    if (wantarray()) {
        return @non_core;
    } else {
        push @{$self->{core_obj}->{_non_core_deps}}, @non_core;
        return $self->{core_obj};
    }
}

sub filter_non_proj_modules {
    my ($self, $modules) = @_;

    my $pipe = IO::Pipe->new();
    my $pid = fork;
    defined($pid) or die "Can't fork for filtering project modules: $!\n";

    if ($pid) {
        $pipe->reader();
        my %non_proj_or_cached = %{ fd_retrieve($pipe) };
        
        if (wantarray()) {
            return %non_proj_or_cached;
        } else {
            $self->{core_obj}->{_non_proj_or_cached} = \%non_proj_or_cached;
            return $self->{core_obj};
        }
    } else {
        local @INC = $self->{core_obj}->inc_dirs();
        my %non_proj_or_cached;
        for my $non_core (@$modules) {
            eval {
                require $non_core;
                1;
            } or do {
                $self->{_logger}->warn("Cannot load $non_core module: $@");
            };
            # If use-cache options was set, we consider fatlib directory as part
            # of project directory so all modules cached by previous executions 
            # of script will be considered as project modules
            my @proj_dir = ($self->{core_obj}->{use_cache})
                ? ($self->{core_obj}->{fatlib_dir}, @{$self->{core_obj}->{proj_dir}})
                : @{$self->{core_obj}->{proj_dir}};
            if (not grep {$INC{$non_core} =~ catfile($_, $non_core)} @proj_dir)
            {
                push @{$non_proj_or_cached{non_proj}}, $non_core;
            }
            if ($self->{core_obj}->{use_cache}) {
                if ( $INC{$non_core} =~ catfile($self->{core_obj}->{fatlib_dir}, $non_core) )
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

    my $pipe = IO::Pipe->new();
    my $pid = fork;
    defined($pid) or die "Can't fork for filtering XS modules: $!\n";

    if ($pid) {
        $pipe->reader();
        my @xsed_modules = @{ fd_retrieve($pipe) };
        
        if (wantarray()) {
            return @xsed_modules;
        } else {
            $self->{core_obj}->{_xsed} = \@xsed_modules;
            return $self->{core_obj};
        }
    } else {
        local @INC = $self->{core_obj}->inc_dirs(proj_dir => 0);
        use DynaLoader;
        my @xsed_modules;
        for my $module_file (@$modules) {
            my $module_name = 
                module_notation_conv($module_file, direction => "to_dotted");
            eval {
                require $module_file;
                1;
            } or do {
                $self->{_logger}->warn("Failed to load ${module_file}: $@");
            };
            if ( grep { $module_name eq $_ } @DynaLoader::dl_modules ) {
                push @xsed_modules, $module_file;
            }
        }
        $pipe->writer();
        $pipe->autoflush(1);
        store_fd(\@xsed_modules, $pipe);
        exit 0;
    }
}

1;