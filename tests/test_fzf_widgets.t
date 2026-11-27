use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use TestHelpers;
use Test::More;

my $root = absolute_path("$FindBin::Bin/..");

sub setup {
    my ($self) = @_;
    $self->{root} = tempdir( 'fzf-status-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$self->{root}/picked.txt", 'text' );
}

sub pick {
    my ( $self, $widget, $selection, $mode, $wrapped, $execute, $count_events ) = @_;
    my $result = run_command(
        [ 'fish', '--no-config', '-c', <<'FISH' ],
source "$TEST_DOTFILES/fish/functions/_fzf.fish"
source "$TEST_DOTFILES/fish/functions/rendezvous.fish"
set -g aqsnow_fzf_diralis
set -g CDPATH .
set -g fish_bind_mode "$TEST_MODE"
set -g mode_events 0
function mode_changed --on-variable fish_bind_mode
    set -g mode_events $(math "$mode_events + 1")
end
set -g inserted ''
set -g executed 0
function rendezvous_init
    set -gx RENDEZVOUS_FISH "$TEST_ROOT/request"
    printf '' > "$RENDEZVOUS_FISH"
end
function __fzf_parse_commandline
    printf '.\0\0\0'
end
function commandline
    switch "$argv[1]"
        case --paging-mode
            return 1
        case -L
            printf 1
        case -f
            test "$argv[2]" != execute; or set -g executed 1
        case -rt
            set -g inserted "$argv[3]"
        case --cut-at-cursor --tokens-expanded
            printf 'echo\n'
        case --current-token -t
            printf ''
        case '*'
            if not set -q argv[1]
                if set -q argv[2]
                    set -g inserted "$argv[2]"
                else
                    printf 'echo '
                end
            else if test "$argv[1]" = --
                set -g inserted "$argv[2]"
            else
                printf 'echo '
            end
    end
end
function complete
    printf 'picked.txt\tFile\n'
end
function fzfp
    printf 'picked.txt\0'
end
function fzf
    cat >/dev/null
    if test "$TEST_SELECTION" = selected
        if test "$TEST_EXECUTE" = 1
            printf exec > "$RENDEZVOUS_FISH"
        end
        if test "$TEST_WIDGET" = fzf_complete
            printf 'picked.txt\n'
        else
            printf 'picked.txt\0'
        end
        return 0
    end
    test "$TEST_SELECTION" = empty; and return 0
    return 130
end
if test "$TEST_WRAPPED" = 1
    _fzf "$TEST_WIDGET"
else
    "$TEST_WIDGET"
end
set -l code "$status"
set -l changed no
test -n "$inserted"; and set changed yes
printf '%s:%s:%s:%s\n' "$code" "$fish_bind_mode" "$changed" "$executed"
if test "$TEST_COUNT_EVENTS" = 1
    printf '%s\n' "$mode_events"
end
FISH
        {
            cwd => $self->{root},
            env => {
                %ENV,
                TEST_ROOT         => $self->{root},
                TEST_DOTFILES     => $root,
                TEST_WIDGET       => $widget,
                TEST_SELECTION    => $selection,
                TEST_MODE         => $mode,
                TEST_WRAPPED      => $wrapped      // 0,
                TEST_EXECUTE      => $execute      // 0,
                TEST_COUNT_EVENTS => $count_events // 0,
                XDG_DATA_HOME     => "$self->{root}/data",
            },
            check => 1,
        }
    );
    is( $result->{stderr}, '', "$widget has no diagnostics" );
    return $result->{stdout};
}

sub widgets_report_selection {
    my ($self) = @_;
    for my $widget (qw(fzf_path_widget fzf-history-widget fzf_complete)) {
        for my $selection (qw(cancelled empty selected)) {
            my $selected = $selection eq 'selected';
            is(
                pick( $self, $widget, $selection, 'default' ),
                ( $selected ? '0:default:yes:0' : '1:default:no:0' ) . "\n",
                "$widget reports $selection without changing mode"
            );
        }
    }
}

sub wrapper_changes_mode_only_after_selection {
    my ($self) = @_;
    for my $widget (
        qw(fzf-path-widget fzf-recent-widget fzf-history-widget fzf_complete fzf-path-first-widget fzf-history-first-widget)
      )
    {
        for my $mode (qw(default insert)) {
            for my $selection (qw(cancelled empty selected)) {
                my $selected = $selection eq 'selected';
                is(
                    pick( $self, $widget, $selection, $mode, 1 ),
                    ( $selected ? '0:insert:yes:0' : "1:$mode:no:0" ) . "\n",
                    "$widget $selection from $mode mode"
                );
            }
        }
    }
}

sub selected_execution_request_runs_once {
    my ($self) = @_;
    is( pick( $self, 'fzf-path-widget', 'selected', 'default', 1, 1 ),
        "0:insert:yes:1\n", 'Alt-Enter selection queues execution and enters Insert mode' );
}

sub mode_assignments_only_run_for_changes {
    my ($self) = @_;
    for my $mode (qw(default insert)) {
        for my $execute ( 0, 1 ) {
            my $events = $mode eq 'default' ? 1 : 0;
            is(
                pick( $self, 'fzf-path-widget', 'selected', $mode, 1, $execute, 1 ),
                "0:insert:yes:$execute\n$events\n",
                'picker and rendezvous avoid redundant mode-change events'
            );
        }
    }
}

run_cases(
    {
        widgets_report_selection                  => \&widgets_report_selection,
        wrapper_changes_mode_only_after_selection => \&wrapper_changes_mode_only_after_selection,
        selected_execution_request_runs_once      => \&selected_execution_request_runs_once,
        mode_assignments_only_run_for_changes     => \&mode_assignments_only_run_for_changes,
    },
    \&setup
);
