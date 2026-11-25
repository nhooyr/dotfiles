use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub file_arguments_preserve_order_and_quoting {
    plan skip_all => 'AppleScript requires macOS' unless $^O eq 'darwin';
    my $temporary = tempdir( 'nvim-open-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    my $compiled  = "$temporary/app.scpt";
    run_command( [ 'osacompile', '-o', $compiled, "$root/nvim/app/nvim.applescript" ], { check => 1 } );
    write_file( "$temporary/driver.applescript", <<'APPLESCRIPT' );
on run argv
    set appScript to load script (POSIX file (item 1 of argv))
    set inputFiles to {}
    repeat with i from 2 to count argv
        set end of inputFiles to POSIX file (item i of argv)
    end repeat
    return appScript's commandForFiles(inputFiles)
end run
APPLESCRIPT
    my @paths = map { "$temporary/file $_ ' \\ [x] \$dollar.txt" } 1 .. 20;
    write_file( $_, '' ) for @paths;
    for my $count ( 0, 1, 20 ) {
        my @files = @paths[ 0 .. $count - 1 ];
        my $command =
          run_command( [ 'osascript', "$temporary/driver.applescript", $compiled, @files ], { check => 1 } )
          ->{stdout};
        $command =~ s/\n\z//;
        my $result = run_command(
            [
                'fish', '--no-config', '-c', 'function nvim; printf "%s\\0" $argv; end; eval "$argv[1]"',
                '--',   $command
            ],
            { check => 1 }
        );
        is_deeply(
            [ split /\0/, $result->{stdout} ],
            [ '--',       @files ],
            "$count files retain their order and literal characters"
        );
    }
}

run_cases( { file_arguments_preserve_order_and_quoting => \&file_arguments_preserve_order_and_quoting } );
