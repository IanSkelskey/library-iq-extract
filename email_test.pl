#!/usr/bin/perl

use strict;
use warnings;
use lib 'lib';  # Ensure the script can find the Email module
use Email qw(send_email);
use Logging qw(init_logging logmsg);
use Utils qw(read_config);

# Read configuration file
my $config_file = 'config/library_config.conf';
my $conf = read_config($config_file);

# Initialize logging
init_logging($conf->{logfile}, 1);

# Get email details from configuration
my $from = $conf->{fromemail};
my @recipients = split /,/, $conf->{alwaysemail};
my $subject = 'Test Email from LibraryIQ Extract';
my $body = <<"END_MESSAGE";
This is a test email from the LibraryIQ Extract script.

Details:
---------
Start Time: @{[scalar localtime]}
End Time: @{[scalar localtime]}
Elapsed Time: 00:00:00
Mode: TEST
Chunk Size: 500

Thank you,
LibraryIQ Extract Script
END_MESSAGE

# Send the email
my $email_success = send_email($from, \@recipients, $subject, $body);

if ($email_success) {
    logmsg("INFO", "Test email sent to: ".join(',', @recipients)
        ." from: $from"
        ." with subject: $subject"
        ." and body: $body");
} else {
    logmsg("ERROR", "Failed to send test email. Check the configuration file. Continuing...");
}