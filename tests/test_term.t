use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;
use MIME::Base64 qw(decode_base64);

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    plan skip_all => 'Terminal color archives require macOS' unless $^O eq 'darwin';
    $self->{temporary} = tempdir( 'term-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    $self->{term}      = "$self->{temporary}/term";
    $self->{theme}     = "$self->{temporary}/vscode/theme";
    make_path( $self->{term}, $self->{theme} );
    copy_preserve( "$root/term/$_", "$self->{term}/$_" )
      for qw(generate.pl theme.json.in 0nhooyr.terminal README.md);
}

sub generate {
    my ($self) = @_;
    return run_command( [ perl_executable(), "$self->{term}/generate.pl" ],
        { cwd => $self->{temporary}, check => 1 } );
}

sub theme {
    my ($self) = @_;
    my $json = read_file("$self->{theme}/theme.json");
    $json =~ s{^\s*//.*$}{}mg;
    return decode_json($json);
}

sub help_flags {
    my ($self) = @_;
    for my $flag ( '-h', '--help' ) {
        my $result = run_command( [ perl_executable(), "$self->{term}/generate.pl", $flag ] );
        is( $result->{returncode}, 0, "$flag succeeds" );
        like( $result->{stdout}, qr/usage: .*generate\.pl/, "$flag prints usage" );
    }
}

sub repeated_colors_share_one_conversion {
    my ($self)  = @_;
    my $profile = read_file("$self->{term}/0nhooyr.terminal");
    my ($color) = $profile =~ m{<key>ANSIRedColor</key>\s*<data>(.*?)</data>}s;
    $profile =~ s{(<key>[^<]*Color</key>\s*<data>).*?(</data>)}{$1$color$2}gs;
    write_file( "$self->{term}/0nhooyr.terminal", $profile );
    my $bin = "$self->{temporary}/bin";
    make_path($bin);
    write_file( "$bin/plutil", <<'SH' );
#!/bin/sh
printf 'conversion\n' >> "$TERM_CONVERSIONS"
exec /usr/bin/plutil "$@"
SH
    chmod 0755, "$bin/plutil" or die $!;
    local $ENV{PATH}             = "$bin:$ENV{PATH}";
    local $ENV{TERM_CONVERSIONS} = "$self->{temporary}/conversions";
    generate($self);
    is( read_file( $ENV{TERM_CONVERSIONS} ), "conversion\n", 'identical colors need only one conversion' );
}

sub palette_drives_both_themes {
    my ($self)  = @_;
    my $profile = read_file("$self->{term}/0nhooyr.terminal");
    my ($red)   = $profile =~ m{<key>ANSIRedColor</key>\s*<data>(.*?)</data>}s;
    my ($green) = $profile =~ m{<key>ANSIGreenColor</key>\s*<data>(.*?)</data>}s;
    $profile =~ s{(<key>ANSIBlueColor</key>\s*<data>).*?(</data>)}{$1$red$2}s;
    $profile =~ s{(<key>ANSIBrightYellowColor</key>\s*<data>).*?(</data>)}{$1$green$2}s;
    write_file( "$self->{term}/0nhooyr.terminal", $profile );
    generate($self);
    my $theme = theme($self);
    is( $theme->{colors}{'terminal.ansiBlue'}, '#B60000', 'regular ANSI slot follows its palette entry' );
    is( $theme->{colors}{'terminal.ansiBrightBlue'},    '#0000B3', 'bright slot remains independent' );
    is( $theme->{colors}{'textLink.foreground'},        '#B60000', 'semantic colors follow the palette' );
    is( $theme->{colors}{'editor.findMatchBackground'}, '#0A5C07', 'match backgrounds use bright yellow' );
    is( $theme->{colors}{'editor.findMatchForeground'}, '#000000', 'matches retain black text' );
    is( $theme->{colors}{'terminal.ansiYellow'}, '#CC0077',
        'regular yellow stays independent of highlights' );
    is( $theme->{colors}{'widget.shadow'},      '#00000018', 'alpha suffixes are preserved' );
    is( $theme->{colors}{'disabledForeground'}, '#767676',   'UI shading is preserved' );
    my $mate = decode_json(
        run_command( [ 'plutil', '-convert', 'json', '-o', '-', "$self->{theme}/nhooyr.tmTheme" ],
            { check => 1 } )->{stdout}
    );
    is( $mate->{settings}[0]{settings}{findHighlight}, '#0A5C07', 'TextMate uses the same match color' );
    my @tokens = map { +{ %$_, scope => join( ', ', @{ $_->{scope} } ) } } @{ $theme->{tokenColors} };
    is_deeply( [ @{ $mate->{settings} }[ 1 .. $#{ $mate->{settings} } ] ],
        \@tokens, 'both themes share all token rules' );
    like(
        read_file("$self->{term}/README.md"),
        qr/\| Blue \| `#B60000` \| `#0000B3` \|/,
        'the README palette is synchronized'
    );
}

sub compacts_srgb_without_changing_profile_settings {
    my ($self) = @_;
    my $before = read_file("$self->{term}/0nhooyr.terminal");
    generate($self);
    my $after = read_file("$self->{term}/0nhooyr.terminal");
    for my $text ( $before, $after ) {
        $text =~ s{(<key>[^<]*Color</key>\s*<data>).*?(</data>)}{$1$2}gs;
    }
    is( $after, $before, 'non-color settings and formatting are untouched' );
    my $profile = read_file("$self->{term}/0nhooyr.terminal");
    my $count   = 0;
    while ( $profile =~ m{<key>([^<]*Color)</key>\s*<data>(.*?)</data>}gs ) {
        my ( $name, $bytes ) = ( $1, decode_base64($2) );
        cmp_ok( length($bytes), '<', 400, "$name uses a compact archive" );
        open my $archive, '>:raw', "$self->{temporary}/color.bin" or die $!;
        print {$archive} $bytes;
        close $archive or die $!;
        my $xml = run_command( [ 'plutil', '-convert', 'xml1', '-o', '-', "$self->{temporary}/color.bin" ],
            { check => 1 } )->{stdout};
        like( $xml, qr{<key>NSID</key>\s*<integer>7</integer>}, "$name uses sRGB" );
        unlike( $xml, qr/NSICC|NSRGB|NSLinearExposure/, "$name omits redundant color data" );
        $count++;
    }
    is( $count, 16, 'all ANSI colors are compacted' );
    my @files = (
        "$self->{term}/0nhooyr.terminal", "$self->{term}/README.md",
        "$self->{theme}/theme.json",      "$self->{theme}/nhooyr.tmTheme"
    );
    my @contents = map { read_file($_) } @files;
    generate($self);
    is_deeply( [ map { read_file($_) } @files ], \@contents, 'generation is byte-for-byte idempotent' );
}

sub converts_display_p3_to_srgb {
    my ($self) = @_;
    my $js = <<'JAVASCRIPT';
ObjC.import('AppKit');
var color = $.NSColor.colorWithDisplayP3RedGreenBlueAlpha(0.6908678298, 0, 0.4549807227, 1);
var archive = $.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(color, true, null);
archive.base64EncodedStringWithOptions(0).js;
JAVASCRIPT
    my $data    = run_command( [ 'osascript', '-l', 'JavaScript', '-e', $js ], { check => 1 } )->{stdout};
    my $profile = read_file("$self->{term}/0nhooyr.terminal");
    $profile =~ s{(<key>ANSIYellowColor</key>\s*<data>).*?(</data>)}{$1$data$2}s;
    write_file( "$self->{term}/0nhooyr.terminal", $profile );
    generate($self);
    is( theme($self)->{colors}{'terminal.ansiYellow'}, '#C10077', 'P3 colors convert before quantization' );
}

sub string_and_global_token_rules {
    my ($self) = @_;
    my $json = read_file("$self->{term}/theme.json.in");
    $json =~ s{^\s*//.*$}{}mg;
    my $template = decode_json($json);
    $template->{tokenColors}[0]{scope} = 'keyword.control';
    $template->{tokenColors}[0]{name}  = "caf\x{e9} \x{1f600}";
    push @{ $template->{tokenColors} }, { settings => { foreground => '${black}' } };
    write_file( "$self->{term}/theme.json.in", JSON::PP->new->ascii->encode($template) );
    generate($self);
    my $mate = JSON::PP->new->decode(
        run_command( [ 'plutil', '-convert', 'json', '-o', '-', "$self->{theme}/nhooyr.tmTheme" ],
            { check => 1 } )->{stdout}
    );
    is( $mate->{settings}[1]{scope}, 'keyword.control',     'a string scope is preserved' );
    is( $mate->{settings}[1]{name},  "caf\x{e9} \x{1f600}", 'Unicode rule names produce valid UTF-8' );
    ok( !exists $mate->{settings}[-1]{scope}, 'a global rule stays unscoped' );
    is( $mate->{settings}[-1]{settings}{foreground}, '#000000', 'global rules still expand the palette' );
}

run_cases(
    {
        help_flags                                      => \&help_flags,
        repeated_colors_share_one_conversion            => \&repeated_colors_share_one_conversion,
        palette_drives_both_themes                      => \&palette_drives_both_themes,
        compacts_srgb_without_changing_profile_settings => \&compacts_srgb_without_changing_profile_settings,
        converts_display_p3_to_srgb                     => \&converts_display_p3_to_srgb,
        string_and_global_token_rules                   => \&string_and_global_token_rules,
    },
    \&setup
);
