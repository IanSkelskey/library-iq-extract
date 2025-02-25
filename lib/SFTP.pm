package SFTP;

use strict;
use warnings;
use Net::SFTP::Foreign;
use Exporter 'import';
use Logging qw(logmsg);  # Add this line to import the logger

our @EXPORT_OK = qw(do_sftp_upload);


# ----------------------------------------------------------
# do_sftp_upload
# ----------------------------------------------------------
sub do_sftp_upload {
    my ($host, $user, $pass, $remote_dir, $local_file) = @_;

    # Net::SFTP::Foreign usage
    my $sftp = Net::SFTP::Foreign->new($host, user => $user, password => $pass);
    if ($sftp->error) {
        return "SFTP connection failed: " . $sftp->error;
    }

    my $remote_path = "$remote_dir/" . _basename($local_file);
    $sftp->put($local_file, $remote_path)
        or return "SFTP upload of $local_file failed: " . $sftp->error;

    logmsg("INFO", "SFTP uploaded $local_file to $remote_path");
    return '';  # success => empty error message
}

1;