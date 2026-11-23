package TestHelpers;
use strict;
use warnings;
use utf8;
use Exporter 'import';
use Cwd            qw(abs_path getcwd);
use File::Basename qw(dirname basename);
use File::Spec;
use File::Path  qw(make_path remove_tree);
use File::Copy  qw(copy);
use File::Temp  qw(tempdir tempfile);
use JSON::PP    qw(encode_json decode_json);
use List::Util  qw(min max);
use POSIX       qw(WNOHANG);
use Time::HiRes qw(time sleep);
use Time::Local qw(timegm_modern timelocal_modern);
use Test::More;
our @EXPORT =
  qw(which perl_executable run_command read_file write_file join_path absolute_path ancestors file_uri same_file directory_entries shell_quote trim replace_literal split_literal partition_last array_slice string_slice zip_lists enumerate_list unique_values equal_values contains_value count_values read_calls run_cases iso_epoch epoch_iso dirname basename make_path remove_tree copy_preserve tempdir encode_json decode_json min max);

sub perl_executable { return $^X =~ m{/} ? absolute_path($^X) : which($^X); }

sub copy_preserve {
    my ( $source, $target ) = @_;
    copy( $source, $target )                      or die "copy $source to $target: $!\n";
    chmod( ( stat $source )[2] & 07777, $target ) or die "chmod $target: $!\n";
}

sub which {
    my ($name) = @_;
    for my $directory ( split /:/, $ENV{PATH} ) {
        my $path = "$directory/$name";
        return $path if -x $path && !-d $path;
    }
    return;
}

sub read_file {
    my ($path) = @_;
    open my $file, '<:encoding(UTF-8)', $path or die "$path: $!\n";
    local $/;
    return <$file> // '';
}

sub write_file {
    my ( $path, $text ) = @_;
    open my $file, '>:encoding(UTF-8)', $path or die "$path: $!\n";
    print {$file} $text;
    close $file or die "$path: $!\n";
}

sub run_command {
    my ( $command, $options ) = @_;
    $options //= {};
    my ( $in,  $input_path )  = tempfile();
    my ( $out, $output_path ) = tempfile();
    my ( $err, $error_path )  = tempfile();
    binmode $_, ':encoding(UTF-8)' for ( $in, $out, $err );
    print {$in} $options->{input} // '';
    seek $in, 0, 0;
    my $pid = fork();
    die "fork: $!\n" unless defined $pid;

    if ( !$pid ) {
        chdir $options->{cwd}
          or die "chdir $options->{cwd}: $!\n"
          if defined $options->{cwd};
        %ENV = %{ $options->{env} } if $options->{env};
        utf8::encode($_) for grep { utf8::is_utf8($_) } values %ENV;
        open STDIN,  '<&', $in  or die $!;
        open STDOUT, '>&', $out or die $!;
        open STDERR, '>&', $err or die $!;
        my @arguments = @$command;
        utf8::encode($_) for @arguments;
        exec { $arguments[0] } @arguments;
        die "exec $command->[0]: $!\n";
    }
    my $deadline = time + ( $options->{timeout} // 30 );
    while ( waitpid( $pid, WNOHANG ) == 0 ) {
        if ( time > $deadline ) {
            kill 'TERM', $pid;
            sleep 0.1;
            kill 'KILL', $pid;
            waitpid( $pid, 0 );
            die "Command timed out: " . join( ' ', @$command ) . "\n";
        }
        sleep 0.005;
    }
    my $status = $?;
    close $_ for ( $in, $out, $err );
    my $result = {
        returncode => ( $status & 127 ) ? -( $status & 127 ) : $status >> 8,
        stdout     => read_file($output_path),
        stderr     => read_file($error_path),
    };
    unlink $input_path, $output_path, $error_path;
    die "Command failed ($result->{returncode}): " . join( ' ', @$command ) . "\n$result->{stderr}"
      if $options->{check} && $result->{returncode};
    return $result;
}

sub join_path {
    my $path = File::Spec->catfile(@_);
    utf8::upgrade($path);
    return $path;
}
sub absolute_path { return abs_path( $_[0] ) // File::Spec->rel2abs( $_[0] ); }

sub ancestors {
    my ($path) = @_;
    my @parents;
    while ( dirname($path) ne $path ) {
        $path = dirname($path);
        push @parents, $path;
    }
    return \@parents;
}

sub file_uri {
    my $path = absolute_path( $_[0] );
    utf8::encode($path);
    $path =~ s{([^A-Za-z0-9/_.~-])}{sprintf '%%%02X', ord $1}ge;
    return 'file://' . $path;
}

sub same_file {
    my @first  = stat $_[0];
    my @second = stat $_[1];
    return
         @first
      && @second
      && $first[0] == $second[0]
      && $first[1] == $second[1];
}

sub directory_entries {
    my ($path) = @_;
    opendir my $directory, $path or die "$path: $!\n";
    my @names = map { join_path( $path, $_ ) }
      grep { $_ ne '.' && $_ ne '..' } readdir $directory;
    closedir $directory;
    return \@names;
}
sub shell_quote { my $text = $_[0]; $text =~ s/'/'"'"'/g;    return "'$text'"; }
sub trim        { my $text = $_[0]; $text =~ s/^\s+|\s+$//g; return $text; }

sub replace_literal {
    my ( $text, $from, $to ) = @_;
    $text =~ s/\Q$from\E/$to/g;
    return $text;
}

sub split_literal {
    my ( $text, $separator, $max ) = @_;
    return [ split /\Q$separator\E/, $text, defined($max) ? $max + 1 : -1 ];
}

sub partition_last {
    my ( $text, $separator ) = @_;
    my $index = rindex( $text, $separator );
    return [ '', '', $text ] if $index < 0;
    return [ substr( $text, 0, $index ), $separator, substr( $text, $index + length($separator) ) ];
}

sub array_slice {
    my ( $items, $start, $end ) = @_;
    $start //= 0;
    $end   //= scalar @$items;
    $start += @$items if $start < 0;
    $end   += @$items if $end < 0;
    return [ @$items[ $start .. $end - 1 ] ];
}

sub string_slice {
    my ( $text, $start, $end ) = @_;
    $start //= 0;
    $end   //= length $text;
    $start += length($text) if $start < 0;
    $end   += length($text) if $end < 0;
    return substr( $text, $start, $end - $start );
}

sub zip_lists {
    my @lists = @_;
    my $count = min( map { scalar @$_ } @lists );
    return [
        map {
            my $index = $_;
            [ map { $_->[$index] } @lists ]
        } 0 .. $count - 1
    ];
}

sub enumerate_list {
    my ($list) = @_;
    return [ map { [ $_, $list->[$_] ] } 0 .. $#$list ];
}

sub unique_values {
    my %seen;
    return [ sort grep { !$seen{$_}++ } @{ $_[0] } ];
}

sub equal_values {
    return JSON::PP->new->canonical->encode( $_[0] ) eq JSON::PP->new->canonical->encode( $_[1] );
}

sub contains_value {
    my ( $container, $value ) = @_;
    return scalar grep { equal_values( $_, $value ) } @$container
      if ref($container) eq 'ARRAY';
    return exists $container->{$value} if ref($container) eq 'HASH';
    return index( $container, $value ) >= 0;
}
sub count_values { my %counts; ++$counts{$_} for @{ $_[0] }; return \%counts; }

sub read_calls {
    my ($path) = @_;
    return [] unless -f $path;
    my @fields = split /\0/, read_file($path), -1;
    pop @fields;
    my @calls;
    while (@fields) {
        my $kind  = shift @fields;
        my $count = shift @fields;
        my @args  = splice @fields, 0, $count;
        my $call  = { kind => $kind, args => \@args };
        if ( $kind eq 'git' ) {
            my $index = 0;
            while ( $index < @args ) {
                if ( $args[$index] =~ /\A(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env)\z/ ) {
                    $index += 2;
                }
                elsif ( $args[$index] =~ /^-/ ) { ++$index; }
                else                            { last; }
            }
            $call->{command} = $args[$index] // '';
        }
        push @calls, $call;
    }
    return \@calls;
}

sub run_cases {
    my ( $cases, $setup ) = @_;
    binmode Test::More->builder->output,         ':encoding(UTF-8)';
    binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
    binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';
    if ( @ARGV && $ARGV[0] eq '--list' ) {
        print "$_\n" for sort keys %$cases;
        exit;
    }
    my @selected = @ARGV ? @ARGV : sort keys %$cases;
    for my $name (@selected) {
        die "Unknown test: $name\n" unless $cases->{$name};
        subtest $name => sub {
            my $self = {};
            my $ok =
              eval { $setup->($self) if $setup; $cases->{$name}->($self); 1; };
            fail($@) unless $ok;
            remove_tree( $self->{temporary} )
              if $self->{temporary} && -d $self->{temporary};
            done_testing;
        };
    }
    done_testing;
}

sub iso_epoch {
    my ($value) = @_;
    $value =~ /\A(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?(Z|([+-])(\d\d):?(\d\d))?)?\z/
      or die "Bad ISO date $value\n";
    my ( $year, $month, $day, $hour, $minute, $second, $zone, $sign, $zone_hour, $zone_minute ) =
      ( $1, $2, $3, $4, $5, $6, $7, $8, $9, $10 );
    my @parts = ( $second // 0, $minute // 0, $hour // 0, $day, $month - 1, $year );
    my $epoch =
      defined($zone) ? timegm_modern(@parts) : timelocal_modern(@parts);
    $epoch -= ( $sign eq '+' ? 1 : -1 ) * ( $zone_hour * 3600 + $zone_minute * 60 )
      if defined $sign;
    return $epoch;
}

sub epoch_iso {
    my @time = gmtime $_[0];
    return sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ', $time[5] + 1900,
      $time[4] + 1, $time[3], $time[2], $time[1],
      $time[0];
}
1;
