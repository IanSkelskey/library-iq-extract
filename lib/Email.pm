package Email;

use strict;
use warnings;
use Email::MIME;
use Email::Sender::Simple 'sendmail';
use Exporter 'import';
use Logging qw(logmsg);
use Try::Tiny;

our @EXPORT_OK = qw(send_email);

# ----------------------------------------------------------
# send_email - minimal example
# ----------------------------------------------------------
sub send_email {
    my ($from, $to_ref, $subject, $body) = @_;
    
    # Remove duplicate email addresses
    my %seen;
    my @unique_recipients = grep { !$seen{$_}++ } @$to_ref;

    my $email = Email::MIME->create(
        header_str => [
            From    => $from,
            To      => join(",", @unique_recipients),
            Subject => $subject,
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'UTF-8',
        },
        body_str => $body
    );

    my $success = 1;
    try {
        sendmail($email);
    } catch {
        my $error = $_;
        if ($error =~ /connection refused/i || $error =~ /could not connect/i) {
            logmsg("ERROR", "Failed to send email: Relay server not available");
        } else {
            logmsg("ERROR", "Failed to send email: $error");
        }
        $success = 0;
    };
    return $success;
}

1;