use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $program = absolute_path("$FindBin::Bin/../bin/hpath");

sub home_path_boundaries {
    for my $case (
        [ '/Users/example',                        '~' ],
        [ '/Users/example/project',                '~/project' ],
        [ 'Installed /Users/example/project',      'Installed ~/project' ],
        [ '"/Users/example/project"',              '"~/project"' ],
        [ "'/Users/example/project'",              "'~/project'" ],
        [ '(/Users/example/project)',              '(~/project)' ],
        [ '[/Users/example/project]',              '[~/project]' ],
        [ '</Users/example/project>',              '<~/project>' ],
        [ 'path=/Users/example/project',           'path=~/project' ],
        [ 'path:/Users/example/project',           'path:~/project' ],
        [ 'paths,/Users/example/project',          'paths,~/project' ],
        [ '/Users/example/a,/Users/example/b',     '~/a,~/b' ],
        [ '/Volumes/backup/Users/example/project', '/Volumes/backup/Users/example/project' ],
        [ '/Users/example-other/project',          '/Users/example-other/project' ],
      )
    {
        my $result =
          run_command( [$program], { input => $case->[0], env => { %ENV, HOME => '/Users/example' } } );
        is( $result->{returncode}, 0,          $result->{stderr} );
        is( $result->{stdout},     $case->[1], $case->[0] );
    }
}

run_cases( { home_path_boundaries => \&home_path_boundaries } );
