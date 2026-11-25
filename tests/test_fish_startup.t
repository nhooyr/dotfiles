use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{temporary} = tempdir( 'fish-startup-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $temp = $self->{temporary};
    $self->{brew} = "$temp/homebrew";
    make_path( "$temp/dotfiles/fish", "$temp/home", "$self->{brew}/bin", "$self->{brew}/sbin" );
    my $config = read_file("$root/fish/config.fish");
    $config =~ s{\Q/opt/homebrew\E}{$self->{brew}}g;
    write_file( "$temp/dotfiles/fish/config.fish", $config );
    symlink "$root/fish/$_.fish", "$temp/dotfiles/fish/$_.fish" or die $! for qw(git prompt cd);

    for my $command (qw(brew tabs)) {
        write_file( "$self->{brew}/bin/$command", <<'SH' );
#!/bin/sh
printf '%s\n' "$0" >> "$TEST_CALLS"
exit 99
SH
        chmod 0755, "$self->{brew}/bin/$command" or die $!;
    }
    write_file( "$temp/__aqsnow_ssh_keychain_loaded", '' );
    $self->{env} = {
        ( map { $_ => $ENV{$_} } grep { !/^HOMEBREW_/ && $_ ne 'MANPATH' && $_ ne 'INFOPATH' } keys %ENV ),
        HOME            => "$temp/home",
        PATH            => "$self->{brew}/bin:$ENV{PATH}",
        TMPDIR          => $temp,
        XDG_CONFIG_HOME => "$temp/config",
        XDG_DATA_HOME   => "$temp/data",
        TEST_CONFIG     => "$temp/dotfiles/fish/config.fish",
        TEST_CALLS      => "$temp/calls",
        TEST_OUTPUT     => "$temp/environment.json",
        TEST_PERL       => perl_executable(),
        TERM            => 'dumb',
    };
}

sub startup {
    my ( $self, $interactive ) = @_;
    my $script = <<'FISH';
source "$TEST_CONFIG"; or exit "$status"
source "$TEST_CONFIG"; or exit "$status"
command "$TEST_PERL" -MJSON::PP -e 'print encode_json({map {$_ => $ENV{$_}} qw(HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY MANPATH INFOPATH PATH LESS)})' > "$TEST_OUTPUT"
FISH
    my $result = run_command(
        [ 'fish', '--no-config', ( $interactive ? ('-i') : () ), '-c', $script ],
        { cwd => $self->{temporary}, env => $self->{env}, check => 1 }
    );
    is( $result->{stderr}, '', 'startup has no diagnostics' );
    ok( !-e $self->{env}{TEST_CALLS}, 'startup does not invoke brew or tabs' );
    return decode_json( read_file( $self->{env}{TEST_OUTPUT} ) );
}

sub fresh_environment {
    my ($self) = @_;
    my $env = startup($self);
    is( $env->{HOMEBREW_PREFIX},     $self->{brew},          'exports the Homebrew prefix' );
    is( $env->{HOMEBREW_CELLAR},     "$self->{brew}/Cellar", 'exports the Cellar' );
    is( $env->{HOMEBREW_REPOSITORY}, $self->{brew},          'exports the repository' );
    is( $env->{MANPATH},             undef,                  'leaves an unset MANPATH to system defaults' );
    is( $env->{INFOPATH},            "$self->{brew}/share/info:", 'keeps the default Info search path' );
    my @path = split /:/, $env->{PATH};
    is_deeply(
        [ @path[ 0, 1 ] ],
        [ "$self->{brew}/bin", "$self->{brew}/sbin" ],
        'prepends bin and sbin in order'
    );
    is( scalar( grep { $_ eq "$self->{brew}/bin" || $_ eq "$self->{brew}/sbin" } @path ),
        2, 'reloading does not duplicate Homebrew paths' );
}

sub existing_search_paths {
    my ($self) = @_;
    $self->{env}{MANPATH}  = '::/custom/man::';
    $self->{env}{INFOPATH} = '/custom/info:/other/info';
    my $env = startup($self);
    is( $env->{MANPATH}, ':/custom/man', 'preserves custom man pages and includes the default search path' );
    is(
        $env->{INFOPATH},
        "$self->{brew}/share/info:/custom/info:/other/info",
        'preserves custom Info paths without duplicating the Homebrew path on reload'
    );
}

sub inherited_environment {
    my ($self) = @_;
    $self->{env}{HOMEBREW_PREFIX}     = '/inherited/brew';
    $self->{env}{HOMEBREW_CELLAR}     = '/inherited/cellar';
    $self->{env}{HOMEBREW_REPOSITORY} = '/inherited/repository';
    $self->{env}{MANPATH}             = '/inherited/man';
    $self->{env}{INFOPATH}            = '/inherited/info';
    my $env = startup($self);
    is( $env->{$_}, $self->{env}{$_}, "preserves inherited $_" )
      for qw(HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY MANPATH INFOPATH);
}

sub interactive_startup {
    my ($self) = @_;
    my $env = startup( $self, 1 );
    like( $env->{LESS}, qr/(?:^| )-ix4(?: |$)/, 'less still displays four-column tabs' );
}

run_cases(
    {
        fresh_environment     => \&fresh_environment,
        existing_search_paths => \&existing_search_paths,
        inherited_environment => \&inherited_environment,
        interactive_startup   => \&interactive_startup,
    },
    \&setup
);
