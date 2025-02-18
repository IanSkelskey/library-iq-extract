package Logging;

use strict;
use warnings;
use POSIX qw/strftime/;
use Exporter 'import';

our @EXPORT_OK = qw(logmsg init_logging);

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

1;