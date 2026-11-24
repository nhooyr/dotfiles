use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root    = absolute_path("$FindBin::Bin/..");
my $config  = read_file("$root/fish/config.fish");
my $helpers = join "\n", map {
    my ($function) = $config =~ /^(function \Q$_\E\b.*?^end\n)/msg;
    die "Missing Fish function $_\n" unless defined $function;
    $function;
} qw(aqsnow_fzf_diralis_add aqsnow_init_rendezvous realpathc __grep_smart_case grep);
$helpers .= read_file("$root/fish/functions/rootimg.fish");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'fish-helpers-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{root}      = absolute_path( $self->{temporary} );
    make_path("$self->{root}/bin");
    write_file( "$self->{root}/bin/pbcopy", <<'SH' );
#!/bin/sh
cat > "$TEST_ROOT/clipboard"
SH
    chmod 0755, "$self->{root}/bin/pbcopy";
    $self->{env} = {
        %ENV,
        PATH            => "$self->{root}/bin:$ENV{PATH}",
        TMPDIR          => $self->{root},
        XDG_CONFIG_HOME => "$self->{root}/config",
        XDG_DATA_HOME   => "$self->{root}/data",
        TEST_ROOT       => $self->{root},
        TEST_HPATH      => "$root/bin/hpath",
        TEST_PBC        => "$root/bin/pbc",
        TEST_GREP       => which('grep'),
        TERM            => 'dumb',
    };
}

sub fish {
    my ( $self, $body ) = @_;
    return run_command(
        [ 'fish', '--no-config', '-c', "$helpers\n$body" ],
        {
            cwd   => $self->{root},
            env   => $self->{env},
            check => 1,
        }
    );
}

sub aliases_added_after_initialization_are_exported {
    my ($self) = @_;
    my $result = fish( $self, <<'FISH' );
set -g aqsnow_fzf_diralis HOME
aqsnow_init_rendezvous; or exit 1
set -l original "$__aqsnow_rendezvous_dir"
set -g project "$TEST_ROOT"
aqsnow_fzf_diralis_add project; or exit 2
aqsnow_fzf_diralis_add project; or exit 3
aqsnow_init_rendezvous; or exit 4
test "$original" = "$__aqsnow_rendezvous_dir"; or exit 5
fish --no-config -c 'printf "%s\n%s\n" "$AQSNOW_DIRALIS" "$project"'
FISH
    is(
        $result->{stdout},
        "HOME:project\n$self->{root}\n",
        'new aliases reach children without duplicating names or recreating the handoff directory'
    );
    is( $result->{stderr}, '', 'alias initialization has no diagnostics' );
}

run_cases(
    {
        aliases_added_after_initialization_are_exported => \&aliases_added_after_initialization_are_exported,
    },
    \&setup
);
