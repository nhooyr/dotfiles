use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $pbc = absolute_path("$FindBin::Bin/../bin/pbc");

sub setup {
    my ($self) = @_;
    $self->{root}      = tempdir( 'pbc-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{clipboard} = "$self->{root}/clipboard";
    $self->{called}    = "$self->{root}/called";
    write_file( $self->{clipboard},     'keep' );
    write_file( "$self->{root}/pbcopy", <<'SH' );
#!/bin/sh
printf called > "$TEST_CALLED"
cat > "$TEST_CLIPBOARD"
exit "${TEST_COPY_STATUS:-0}"
SH
    chmod 0755, "$self->{root}/pbcopy";
    $self->{env} = {
        %ENV,
        PATH           => "$self->{root}:$ENV{PATH}",
        TEST_CLIPBOARD => $self->{clipboard},
        TEST_CALLED    => $self->{called},
        PBC_SKIP       => '',
    };
}

sub copy_input {
    my ( $self, $input ) = @_;
    return run_command( [$pbc], { env => $self->{env}, input => $input } );
}

sub empty_input_keeps_clipboard {
    my ($self) = @_;
    my $result = copy_input( $self, '' );
    is( $result->{returncode},           0,      $result->{stderr} );
    is( $result->{stdout},               '',     'empty input prints nothing' );
    is( read_file( $self->{clipboard} ), 'keep', 'empty input preserves the clipboard' );
    ok( !-e $self->{called}, 'pbcopy is not started for empty input' );
}

sub nonempty_input_preserves_output_and_trims_one_newline {
    my ($self) = @_;
    for my $input ( 'hello', "one\ntwo\n\n", "\n", 'éclair', "\0binary" ) {
        my $result = copy_input( $self, $input );
        is( $result->{returncode}, 0,      $result->{stderr} );
        is( $result->{stdout},     $input, 'stdout preserves every input byte' );
        ( my $expected = $input ) =~ s/\n\z//;
        is( read_file( $self->{clipboard} ), $expected, 'clipboard trims only the final newline' );
        ok( -e $self->{called}, 'nonempty input starts pbcopy' );
        unlink $self->{called};
    }
}

sub nested_copy_is_passthrough {
    my ($self) = @_;
    $self->{env}{PBC_SKIP} = 1;
    my $result = copy_input( $self, "nested\n" );
    is( $result->{returncode},           0,          $result->{stderr} );
    is( $result->{stdout},               "nested\n", 'nested helper keeps its complete output' );
    is( read_file( $self->{clipboard} ), 'keep',     'nested helper does not change clipboard' );
    ok( !-e $self->{called}, 'nested helper does not start pbcopy' );
}

sub clipboard_failure_is_reported {
    my ($self) = @_;
    $self->{env}{TEST_COPY_STATUS} = 7;
    my $result = copy_input( $self, 'hello' );
    is( $result->{returncode}, 7,       'clipboard failure remains visible' );
    is( $result->{stdout},     'hello', 'clipboard failure does not suppress stdout' );
}

run_cases(
    {
        empty_input_keeps_clipboard                           => \&empty_input_keeps_clipboard,
        nonempty_input_preserves_output_and_trims_one_newline =>
          \&nonempty_input_preserves_output_and_trims_one_newline,
        nested_copy_is_passthrough    => \&nested_copy_is_passthrough,
        clipboard_failure_is_reported => \&clipboard_failure_is_reported,
    },
    \&setup
);
