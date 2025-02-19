package Logging;

use strict;
use warnings;
use POSIX qw/strftime/;
use Exporter 'import';

our @EXPORT_OK = qw(logmsg init_logging logheader);

my $log_file = 'libraryiq_export.log';
my $debug;

# ----------------------------------------------------------
# init_logging - Initialize logging with log file and debug flag
# ----------------------------------------------------------
sub init_logging {
    my ($file, $dbg) = @_;
    $log_file = $file;
    $debug = $dbg;
}

# ----------------------------------------------------------
# logmsg - Log a message with timestamp and log level
# ----------------------------------------------------------
sub logmsg {
    my ($level, $msg) = @_;
    open my $LOG, '>>', $log_file or die "Cannot open $log_file: $!";
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
    print $LOG "[$ts] [$level] $msg\n";
    print "[$ts] [$level] $msg\n" if $debug;  # also echo to stdout if debug
    close $LOG;
}

# ----------------------------------------------------------
# logheader - Log a header with a fixed width and timestamp
# ----------------------------------------------------------
sub logheader {
    my ($header) = @_;
    my $width = 80;
    my $border = '*' x $width;
    my $padding = ' ' x (($width - length($header) - 2) / 2);
    my $formatted_header = "*$padding$header$padding*";
    $formatted_header .= ' ' if length($formatted_header) < $width;
    
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
    my $timestamp = "[$ts]";

    open my $LOG, '>>', $log_file or die "Cannot open $log_file: $!";
    print $LOG "$timestamp\n";
    print $LOG "$border\n";
    print $LOG "$formatted_header\n";
    print $LOG "$border\n";
    close $LOG;

    if ($debug) {
        print "$timestamp\n";
        print "$border\n";
        print "$formatted_header\n";
        print "$border\n";
    }
}

our @EXPORT_OK = qw(logmsg init_logging logheader);

1;