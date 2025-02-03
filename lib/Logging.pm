package Logging;

use strict;
use warnings;
use POSIX qw/strftime/;
use Exporter 'import';

our @EXPORT_OK = qw(logmsg);

# ----------------------------------------------------------
# logmsg - Log a message with timestamp
# ----------------------------------------------------------
sub logmsg {
    my ($msg, $log_file, $debug) = @_;
    open my $LOG, '>>', $log_file or die "Cannot open $log_file: $!";
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime);
    print $LOG "[$ts] $msg\n";
    print "[$ts] $msg\n" if $debug;  # also echo to stdout if debug
    close $LOG;
}

1;