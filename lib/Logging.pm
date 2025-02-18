package Logging;

use strict;
use warnings;
use POSIX qw/strftime/;
use Exporter 'import';

our @EXPORT_OK = qw(logmsg);

# ----------------------------------------------------------
# logmsg - Log a message with timestamp and log level
# ----------------------------------------------------------
sub logmsg {
    my ($level, $msg, $log_file, $debug) = @_;
    open my $LOG, '>>', $log_file or die "Cannot open $log_file: $!";
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
    print $LOG "[$ts] [$level] $msg\n";
    print "[$ts] [$level] $msg\n" if $debug;  # also echo to stdout if debug
    close $LOG;
}

1;