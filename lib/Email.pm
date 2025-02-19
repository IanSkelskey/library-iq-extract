package Email;

use strict;
use warnings;
use Email::MIME;
use Email::Sender::Simple 'sendmail';
use Email::Sender::Transport::SMTP 'SMTP';
use Exporter 'import';

our @EXPORT_OK = qw(send_email);

# ----------------------------------------------------------
# send_email - minimal example
# ----------------------------------------------------------
sub send_email {
    my ($from, $to_ref, $subject, $body) = @_;
    
    my $email = Email::MIME->create(
        header_str => [
            From    => $from,
            To      => join(",", @$to_ref),
            Subject => $subject,
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'UTF-8',
        },
        body_str => $body
    );

    my $transport = Email::Sender::Transport::SMTP->new({
        host          => 'smtp.example.com',  # Replace with your SMTP server
        port          => 587,                 # Replace with your SMTP server port
        sasl_username => 'your_username',     # Replace with your SMTP username
        sasl_password => 'your_password',     # Replace with your SMTP password
        ssl           => 1,                   # Enable SSL if required
    });

    sendmail($email, { transport => $transport });
}

1;