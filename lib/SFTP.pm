package SFTP;

use strict;
use warnings;
use Net::SFTP::Foreign;
use Exporter 'import';

our @EXPORT_OK = qw(do_sftp_upload);

# ----------------------------------------------------------
# do_sftp_upload
# ----------------------------------------------------------
sub do_sftp_upload {
    my ($host, $user, $pass, $remote_dir, $local_file, $logger) = @_;

    # Net::SFTP::Foreign usage
    my $sftp = Net::SFTP::Foreign->new($host, user => $user, password => $pass);
    if ($sftp->error) {
        return "SFTP connection failed: " . $sftp->error;
    }

    my $remote_path = "$remote_dir/" . _basename($local_file);
    $sftp->put($local_file, $remote_path)
        or return "SFTP upload of $local_file failed: " . $sftp->error;

    $logger->("SFTP uploaded $local_file to $remote_path") if $logger;
    return '';  # success => empty error message
}

# ----------------------------------------------------------
# _basename - local helper
# ----------------------------------------------------------
sub _basename {
    my ($path) = @_;
    $path =~ s!^.*/!!;  # remove directories
    return $path;
}

1;