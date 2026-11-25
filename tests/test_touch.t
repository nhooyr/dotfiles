use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $helper = absolute_path("$FindBin::Bin/../fish/functions/touch.fish");

sub setup {
    my ($self) = @_;
    $self->{root} = tempdir( 'touch-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
}

sub touch {
    my ( $self, @paths ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', 'source "$argv[1]"; touch $argv[2..]', '--', $helper, @paths ],
        { cwd => $self->{root} } );
}

sub creates_each_parent {
    my ($self) = @_;
    my @paths  = ( 'one dir/deep/file', '-dash/child/file', q{quote's/$literal;[x]} );
    my $result = touch( $self, '--', @paths );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -f "$self->{root}/$_", "created literal path $_" ) for @paths;
}

sub preserves_timestamp_options {
    my ($self) = @_;
    my $reference = "$self->{root}/reference";
    write_file( $reference, 'reference' );
    utime 946684800, 946684800, $reference or die $!;
    my $result = touch( $self, '-amr', $reference, 'nested/output' );
    is( $result->{returncode},                     0,         $result->{stderr} );
    is( ( stat "$self->{root}/nested/output" )[9], 946684800, 'reference options reach native touch' );
    make_path("$self->{root}/reference-dir");
    utime 946684800, 946684800, "$self->{root}/reference-dir" or die $!;
    $result = touch( $self, '-amr', 'reference-dir/', '--', 'other/output', 'other/directory/' );
    is( $result->{returncode},                    0,         $result->{stderr} );
    is( ( stat "$self->{root}/other/output" )[9], 946684800, 'trailing-slash option values are preserved' );
    ok( -d "$self->{root}/other/directory", 'directory operands are created but excluded from native touch' );
}

sub no_operands_preserve_native_errors {
    my ($self) = @_;
    for my $option ( [], ['-c'] ) {
        my $native  = run_command( [ 'touch', @$option ], { cwd => $self->{root} } );
        my $wrapped = touch( $self, @$option );
        is( $wrapped->{returncode}, $native->{returncode}, 'missing operands retain the native exit status' );
        is( $wrapped->{stderr},     $native->{stderr},     'missing operands retain the native error' );
    }
}

sub creates_trailing_slash_directories {
    my ($self) = @_;
    make_path("$self->{root}/existing");
    utime 946684800, 946684800, "$self->{root}/existing" or die $!;
    my $result = touch( $self, 'file', 'first/nested/', 'second/nested/', 'third/file', 'existing/' );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( -d "$self->{root}/$_", "created directory $_" ) for qw(first/nested second/nested);
    ok( -f "$self->{root}/$_", "created file $_" )      for qw(file third/file);
    is( ( stat "$self->{root}/existing" )[9], 946684800, 'directory timestamps are not touched' );
    $result = touch( $self, 'directory-only/' );
    is( $result->{returncode}, 0, 'directory-only calls succeed without invoking native touch' );
}

sub no_create_stays_no_create {
    my ($self) = @_;
    my $result = touch( $self, '-c', 'missing/child' );
    is( $result->{returncode}, 0, $result->{stderr} );
    ok( !-e "$self->{root}/missing", '-c creates neither parent nor file' );
}

sub stops_after_parent_failure {
    my ($self) = @_;
    write_file( "$self->{root}/blocked", 'keep' );
    my $result = touch( $self, 'blocked/child', 'other/child' );
    isnt( $result->{returncode}, 0, 'a non-directory parent fails' );
    is( read_file("$self->{root}/blocked"), 'keep', 'the blocking file stays intact' );
    ok( !-e "$self->{root}/other/child", 'touch is not run after mkdir fails' );
}

sub reference_is_not_an_output {
    my ($self) = @_;
    my $result = touch( $self, '-r', 'missing-reference/file', 'output' );
    isnt( $result->{returncode}, 0, 'native touch errors are returned' );
    ok( !-e "$self->{root}/missing-reference", 'an option value does not gain a parent directory' );
    ok( !-e "$self->{root}/output",            'a failed reference does not create the output' );
}

run_cases(
    {
        creates_each_parent                => \&creates_each_parent,
        creates_trailing_slash_directories => \&creates_trailing_slash_directories,
        preserves_timestamp_options        => \&preserves_timestamp_options,
        no_operands_preserve_native_errors => \&no_operands_preserve_native_errors,
        no_create_stays_no_create          => \&no_create_stays_no_create,
        stops_after_parent_failure         => \&stops_after_parent_failure,
        reference_is_not_an_output         => \&reference_is_not_an_output,
    },
    \&setup
);
