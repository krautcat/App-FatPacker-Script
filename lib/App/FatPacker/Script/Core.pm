package App::FatPacker::Script::Core;

use strict;
use warnings;
use 5.010001;

use Cwd ();
use File::Spec::Functions qw/catdir rel2abs/;
use List::Util qw/uniq/;
use Log::Any ();

use App::FatPacker::Script::Plugin;
use App::FatPacker::Script::Utils;

=head1 SYNOPSIS

C<App::FatPacker::Script::Core> module is an object-oriented top-level module.
It contains main information about fatpacking, references to filter methods
who are resolved dynamically. All filters must be loaded with
C<L</load_filters>> method before invocation. All filters must began with
C<filter_> prefix.

=head1 OBJECT INTERFACE

=head2 Attributes

=head3 

=cut

sub AUTOLOAD {
    my ($inv) = @_;
    my ( $package, $method ) = our $AUTOLOAD =~ /^(.+)::(.+)$/;

    my ( $err_flag, $exception );

    {
        local $@;
        $err_flag = undef;
        unless ( defined $inv
            && ( !ref $inv or Scalar::Util::blessed $inv)
            && $inv->isa(__PACKAGE__) )
        {
            $err_flag  = 1;
            $exception = $@;
        }
    }
    if ($err_flag) {

        # TODO: die with object
        die "Undefined subroutine &${package}::$method called";
    }

    # Special case
    return if $method eq 'DESTROY';

    my $sub        = undef;
    my $filter_obj = undef;
    if ( $method =~ m/^filter_(.+)*/ ) {
        for my $f ( @{ $inv->{plguins} } ) {
            if ( $f->can($method) ) {
                $sub        = $f->can($method);
                $filter_obj = $f;
            }
        }
    }

    {
        local $@;
        $err_flag = undef;
        unless ( defined $sub and eval { $sub = \&$sub; 1 } ) {
            $err_flag  = 1;
            $exception = $@;
        }
    }
    if ($err_flag) {

        # TODO: die with object
        die qq/Can't locate object method "$method"/
          . qq/via package "$package"/;

    }

    # Change first argument to true object for which we call method and then
    # goto this method.
    $_[0] = $filter_obj;
    goto &$sub;
}

sub can {
    my ( $package, $method ) = @_;
    my $sub = $package->SUPER::can($method);
    return $sub if defined $sub;

    my $filter_obj = undef;
    if ( $method =~ m/^filter_(.+)$/ ) {
        for my $f ( @{ $package->{plugins} } ) {
            if ( $f->can($method) ) {
                $sub        = $f->can($method);
                $filter_obj = $f;
            }
        }
    }

    unless (
        defined $sub and do {
            local $@;
            eval { $sub = \&$sub; 1 };
        }
      )
    {
        return undef;    ## no critic
    }

    return \$filter_obj->$method;
}

=head2 Methods

=head3 new(%arguments)

Create new instance of C<App::FatPacker::Script::Core> object. Constructor
accepts its arguments as flat hash with fat-comma separated values
with comma separator.

    App::FatPacker::Script::Core->new(
        use_cache => 1,
        modules => {
            non_CORE => \@list_of_non_core_modules,
            forced_CORE => \@list_of_forced_core_modules
        }
    )

B<Arguments>

=over 4

=item C<%arguments>:
fat-comma separated hash-like arguments.

=over 8

=item C<script>:
Input script executable which fatpacked version is creating.

=item C<output>:
Output fatpacked file.

=item C<module_dirs>:
Additional direcotries containing non-project Perl modules.

=item C<proj_dirs>:
Project directories containing Perl modules.

=item C<fatlib_dir>:
Directory in which scripts will be temporary copied during fatpacking.

=item C<use_cache>:
Bool-like value enables or disables using cache of previous fatpacking
runnings.

=item C<modules>:
Hash containing info about modules.

=over 12

=item C<forced_CORE>:
Modules from standard library to include into fatpacked script.

=item C<non_CORE>:
Both non-project and not from standard library modules to include into fatpacked
script.

=back

=item C<target_Perl_version>:
Target Perl version relative to which process of determination whether module
is in standard library or not will be going.

=item C<strict>:

=item C<custom_shebang>:
Custom shebang at the beginning of fatpacked script.

=item C<perl_strip>:

=item C<exclude_strip>:

=back

=back

B<Return value>

New instance of C<App::FatPacker::Script::Core> object.

B<Raises>

=cut

sub new {
    my $class  = shift;
    my %params = @_;
    my $self   = bless {}, $class;

    my ( $err_flag, $exception );

    $self->{script} = delete $params{script} || croak("Missing script");
    $self->{output_file} = (
        defined( $self->{output_file} = delete $params{output} )
        ? rel2abs( $self->{output_file} )
        : rel2abs("fatpacked.pl")
    );

    $self->{dir} = (
        defined( $self->{dir} = delete $params{module_dirs} )
        ? [ map { rel2abs($_) } @{ $self->{dir} } ]
        : []
    );

    # Concatenate 'lib' to path if and only if directory isn't absolute
    $self->{proj_dir} = (
        defined( $self->{proj_dir} = delete $params{proj_dirs} )
        ? [
            map { rel2abs($_) eq $_ ? $_ : catdir( rel2abs($_), "lib" ) }
              @{ $self->{proj_dir} }
          ]
        : []
    );

    $self->{fatlib_dir} = (
        defined( $self->{fatlib_dir} = delete $params{fatlib_dir} )
        ? rel2abs( $self->{fatlib_dir} )
        : rel2abs("fatlib")
    );
    $self->{use_cache} = delete $params{use_cache} // 0;

    $self->{forced_CORE_modules} = delete $params{modules}{forced_CORE} // [];
    $self->{non_CORE_modules}    = delete $params{modules}{non_CORE}    // [];
    $self->{target_Perl_version} = delete $params{target_Perl_version}  // $^V;

    $self->{strict}         = delete $params{strict}         // 0;
    $self->{custom_shebang} = delete $params{custom_shebang} // undef;
    $self->{perl_strip}     = delete $params{perl_strip}     // undef;
    $self->{exclude_strip}  = delete $params{exclude_strip}  // [];

    $self->{_logger} = Log::Any->get_logger();

    $self->{_plugin_loader} = App::FatPacker::Script::Plugin->new();
    $self->{plugins} =
      $self->{_plugin_loader}->load_plugins( "App::FatPacker::Script::Filters",
        options => { core_obj => $self } );

    $self->{_non_core_deps}      = [];
    $self->{_non_proj_or_cached} = {};
    $self->{_xsed}               = [];

    return $self;
}

=head3 load_filters(@filter_classes)

Dynamically load filter module, create filter object and push it in array of
avaliable filters.

B<Arguments>

=over 4

=item C<@filter_classes>:
List of filter classes.

=back

=cut

sub load_filters {
    my ( $self, @filter_classes ) = @_;

    my ( $err_flag, $exception );
    for my $f (@filter_classes) {
        $f = module_notation_conv( $f, direction => 'to_fname' );

        {
            local $@;
            ( $err_flag, $exception ) = ( undef, undef );
            unless (
                eval {
                    require $f;
                    push @{ $self->{_filters} }, $f->new( core_obj => $self );
                    1;
                }
              )
            {
                $err_flag  = 1;
                $exception = $@;
            }
        }
        if ($err_flag) {
            $self->{_logger}->error("Can't load filter module $f");
        }
    }

    @{ $self->{_filters} } = uniq @{ $self->{_filters} };
}

=head3 inc_dirs(%arguments)

Return list of directories where modules can be looked up. Includes in ascending order C<@INC>
array, directories from C<dir> attribute, directories from C<fatlib_dir> attribute
(if C<use_cache> attribute is set to logical I<True>) and C<proj_dir> attribute,
if C<proj_dir> parameter passed to method is logical I<True>.

B<Arguments>

=over 4

=item C<%arguments>:
Hash-like fat-comma separated list of comma separated arguments.

=over 8

=item C<proj_dir>:
Bool-like value. When set to logical I<True>, project directories will be
included in returning list of dirs, otherwise, when set to logical I<False>,
project directories will be discarded in return list of directories.

=back

=back

B<Return value>

List of directories for looking up Perl modules.

=cut

sub inc_dirs {
    my $self   = shift;
    my %params = @_;
    $params{proj_dir} = exists $params{proj_dir} ? $params{proj_dir} : 1;

    return uniq(
        ( $params{proj_dir}  ? @{ $self->{proj_dir} } : () ),
        ( $self->{use_cache} ? $self->{fatlib_dir}    : () ),
        @{ $self->{dir} }, @INC
    );
}

sub trace_noncore_dependencies {
    my $self = shift;
    my %args = @_;

    my @opts = ( $self->{script} );
    if ( $self->{quiet} ) {
        push @opts, '2>/dev/null';
    }
    my $trace_opts = '>&STDOUT';

    local $ENV{PERL5OPT} = join ' ',
      ( $ENV{PERL5OPT} || () ), '-MApp::FatPacker::Trace=' . $trace_opts;
    local $ENV{PERL5LIB} = join ':', @{ $self->{proj_dir} },
      ( $self->{use_cache} ? $self->{fatlib_dir} : () ), @{ $self->{dir} },
      ( $ENV{PERL5LIB} || () );

    my @non_core =
      map {
        $args{to_packlist}
          ? module_notation_conv( $_, direction => 'to_fname' )
          : $_;
      }
      grep { not still_core( $_, $self->{target_Perl_version} ); }
      sort { $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger; }
      map {
        my $module = $_;
        chomp($module);
        module_notation_conv(
            $module,
            direction => 'to_dotted',
            relative  => 0
        );
      } qx/$^X @opts/;    ## no critic

    if ( wantarray() ) {
        return @non_core;
    }
    else {
        $self->{_non_core_deps} = \@non_core;
        return $self;
    }
}

sub add_forced_core_dependencies {
    my ( $self, $noncore ) = @_;

    if ( not defined $noncore ) {
        $noncore = $self->{_non_core_deps};
    }

    # Check whether added
    foreach my $forced_core ( @{ $self->{forced_CORE_modules} } ) {
        if (
            Module::CoreList->is_core(
                $forced_core, undef, $self->{target_Perl_version}->numify()
            )
          )
        {
            push @$noncore, $forced_core;
        }
    }
    if ( wantarray() ) {
        return ( sort { $a =~ s!(\w+)!lc($1)!ger cmp $b =~ s!(\w+)!lc($1)!ger }
              @$noncore );
    }
    else {
        return $self;
    }
}

1;
