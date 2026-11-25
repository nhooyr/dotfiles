use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");
my ($function) = read_file("$root/fish/git.fish") =~ /^(function papp\b.*?^end\n)/msg;
die 'missing papp function' unless defined $function;
my $patch = "diff --git a/file b/file\n--- a/file\n+++ b/file\n\@\@ -1 +1 \@\@\n-old\n+new";

sub setup {
    my ($self) = @_;
    $self->{directory} = tempdir( 'papp-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $dir = $self->{directory};
    make_path("$dir/bin");
    write_file( "$dir/file",        "old\n" );
    write_file( "$dir/patch",       $patch );
    write_file( "$dir/bin/pbpaste", '#!' . perl_executable() . "\n" . <<'PERL_STUB' );
use strict;
use warnings;
open my $file, '<', $ENV{TEST_PATCH} or die $!;
{ local $/; print scalar <$file>; }
if ($ENV{TEST_CLIPBOARD_FAILURE}) { warn "clipboard read failed\n"; exit 23 }
PERL_STUB
    chmod 0755, "$dir/bin/pbpaste";
    $self->{env} = {
        %ENV,
        PATH                   => "$dir/bin:$ENV{PATH}",
        TEST_PATCH             => "$dir/patch",
        TEST_CLIPBOARD_FAILURE => 0,
        GIT_CONFIG_GLOBAL      => '/dev/null',
        GIT_CONFIG_NOSYSTEM    => 1,
        XDG_CONFIG_HOME        => "$dir/config",
        XDG_DATA_HOME          => "$dir/data",
    };
    run_command( [ 'git', 'init', '--quiet', $dir ], { env => $self->{env}, check => 1 } );
}

sub apply {
    my ( $self, @args ) = @_;
    return run_command( [ 'fish', '--no-config', '-c', "$function\npapp \$argv", '--', @args ],
        { cwd => $self->{directory}, env => $self->{env} } );
}

sub failed_clipboard_does_not_apply_partial_patch {
    my ($self) = @_;
    $self->{env}{TEST_CLIPBOARD_FAILURE} = 1;
    my $result = apply($self);
    isnt( $result->{returncode}, 0, 'clipboard failure is returned' );
    is( $result->{stderr}, "clipboard read failed\n",  'the original clipboard diagnostic stays visible' );
    is( read_file("$self->{directory}/file"), "old\n", 'a valid partial clipboard patch is not applied' );
}

sub normalizes_final_newline_and_preserves_flags {
    my ($self) = @_;
    my $result = apply( $self, '--check' );
    is( $result->{returncode},                0,       $result->{stderr} );
    is( read_file("$self->{directory}/file"), "old\n", '--check leaves the file alone' );
    $result = apply($self);
    is( $result->{returncode},                0,       $result->{stderr} );
    is( read_file("$self->{directory}/file"), "new\n", 'the patch without a final newline applies' );
    $result = apply( $self, '--reverse' );
    is( $result->{returncode},                0,       $result->{stderr} );
    is( read_file("$self->{directory}/file"), "old\n", '--reverse reaches git apply' );
}

run_cases(
    {
        failed_clipboard_does_not_apply_partial_patch => \&failed_clipboard_does_not_apply_partial_patch,
        normalizes_final_newline_and_preserves_flags  => \&normalizes_final_newline_and_preserves_flags,
    },
    \&setup
);
