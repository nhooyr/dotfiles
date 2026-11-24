use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $fish   = which('fish');
my $helper = absolute_path("$FindBin::Bin/../fish/functions/gbigdirs.fish");

sub setup {
    my ($self) = @_;
    plan skip_all => 'Fish is required' unless $fish;
    $self->{directory} = tempdir( 'gbigdirs-tests-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    make_path( "$self->{directory}/bin", "$self->{directory}/repo/dir" );
    $self->{env} = {
        %ENV,
        PATH           => "$self->{directory}/bin:$ENV{PATH}",
        GBIGDIRS_INPUT => "$self->{directory}/input",
    };
    write_file( "$self->{directory}/bin/gdu", '#!' . perl_executable() . "\n" . <<'PERL' );
use strict;
use warnings;
local $/ = "\0";
open my $input, '>', $ENV{GBIGDIRS_INPUT} or die $!;
while (<STDIN>) {
    print {$input} $_;
    chomp;
    print "10\t$_\n";
}
PERL
    write_file( "$self->{directory}/bin/gnumfmt", "#!/bin/sh\ncat\n" );
    chmod 0755, "$self->{directory}/bin/gdu", "$self->{directory}/bin/gnumfmt";
    run_command( [ 'git', 'init', '-q', "$self->{directory}/repo" ], { check => 1 } );
}

sub tracked_files_only {
    my ($self) = @_;
    my $repo = "$self->{directory}/repo";
    write_file( "$repo/top",       'top' );
    write_file( "$repo/dir/file",  'nested' );
    write_file( "$repo/deleted",   'deleted' );
    write_file( "$repo/untracked", 'untracked' );
    symlink 'top',     "$repo/link"   or die $!;
    symlink 'missing', "$repo/broken" or die $!;
    run_command( [ 'git', '-C', $repo, 'add', '--', 'top', 'dir/file', 'deleted', 'link', 'broken' ],
        { check => 1 } );
    unlink "$repo/deleted" or die $!;
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => $repo, env => $self->{env} } );
    is( $result->{returncode}, 0,  $result->{stderr} );
    is( $result->{stderr},     '', 'no diagnostics for deleted or broken paths' );
    is(
        read_file( $self->{env}{GBIGDIRS_INPUT} ),
        "./broken\0./dir/file\0./link\0./top\0",
        'only existing tracked files and symlinks reach du'
    );
    is( $result->{stdout}, "40\t.\n10\t./dir\n", 'directory totals and order are preserved' );
}

sub outside_repository {
    my ($self) = @_;
    my $result = run_command( [ $fish, '--no-config', '-c', 'source "$argv[1]"; gbigdirs', '--', $helper ],
        { cwd => $self->{directory}, env => $self->{env} } );
    isnt( $result->{returncode}, 0, 'reports Git failure' );
    ok( !-e $self->{env}{GBIGDIRS_INPUT}, 'does not run du outside a repository' );
}

run_cases( { tracked_files_only => \&tracked_files_only, outside_repository => \&outside_repository },
    \&setup );
