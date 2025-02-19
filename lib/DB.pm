package DB;

use strict;
use warnings;
use DBI;
use Exporter 'import';
use Logging qw(logmsg);
use XML::Simple;

our @EXPORT_OK = qw(get_dbh chunked_ids fetch_data_by_ids get_db_config create_history_table);

# ----------------------------------------------------------
# get_dbh - Return a connected DBI handle
# ----------------------------------------------------------
sub get_dbh {
    my ($db_config) = @_;
    my $dsn = "dbi:Pg:dbname=$db_config->{db};host=$db_config->{host};port=$db_config->{port}";
    my $dbh = DBI->connect($dsn, $db_config->{user}, $db_config->{pass},
        { RaiseError => 1, AutoCommit => 1, pg_enable_utf8 => 1 }
    ) or do {
        my $error_msg = "DBI connect error: $DBI::errstr";
        logmsg("ERROR", $error_msg);
        die "$error_msg\n";
    };
    logmsg("INFO", "Successfully connected to the database: $db_config->{db} at $db_config->{host}:$db_config->{port}");
    my $masked_db_config = { %$db_config, pass => '****' };
    logmsg("DEBUG", "DB Config:\n\t" . join("\n\t", map { "$_ => $masked_db_config->{$_}" } keys %$masked_db_config));
    return $dbh;
}

# ----------------------------------------------------------
# get_db_config - Get database configuration from Evergreen config file
# ----------------------------------------------------------
sub get_db_config {
    my ($evergreen_config_file) = @_;
    my $xml = XML::Simple->new;
    my $data = $xml->XMLin($evergreen_config_file);
    return {
        db   => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{db},
        host => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{host},
        port => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{port},
        user => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{user},
        pass => $data->{default}->{apps}->{"open-ils.storage"}->{app_settings}->{databases}->{database}->{pw},
    };
}

# ----------------------------------------------------------
# chunked_ids - Return array of arrays, each containing ID chunks
# ----------------------------------------------------------
sub chunked_ids {
    my ($dbh, $sql, $date_filter, $chunk_size) = @_;

    my @all_ids;
    my $sth = $dbh->prepare($sql);
    if (defined $date_filter) {
        $sth->execute($date_filter, $date_filter);
    } else {
        $sth->execute();
    }

    while (my ($id) = $sth->fetchrow_array) {
        push @all_ids, $id;
    }
    $sth->finish;

    # Now break @all_ids into smaller arrays of size $chunk_size
    my @chunks;
    while (@all_ids) {
        my @slice = splice(@all_ids, 0, $chunk_size);
        push @chunks, \@slice;
    }
    return @chunks;
}

# ----------------------------------------------------------
# fetch_data_by_ids - fetch actual data given an array of IDs
# ----------------------------------------------------------
sub fetch_data_by_ids {
    my ($dbh, $id_chunk, $query) = @_;
    
    # We’ll construct an array expression if needed, or you can do
    # "IN (?,?,?)" approach in the query. For example:
    my $placeholders = join(',', ('?') x @$id_chunk);
    my $sql = $query;
    $sql =~ s/\:id_list/$placeholders/;  # a token in your query e.g. "WHERE bre.id IN (:id_list)"

    my $sth = $dbh->prepare($sql);
    $sth->execute(@$id_chunk);

    my @rows;
    while (my $row = $sth->fetchrow_arrayref) {
        push @rows, [@$row];
    }
    $sth->finish;
    return @rows;
}

# ----------------------------------------------------------
# create_history_table - Create the libraryiq.history table if it doesn't exist
# ----------------------------------------------------------
sub create_history_table {
    my ($dbh, $log_file, $debug) = @_;
    my $sql = q{
        CREATE SCHEMA IF NOT EXISTS libraryiq;
        CREATE TABLE IF NOT EXISTS libraryiq.history (
            id serial PRIMARY KEY,
            key TEXT NOT NULL,
            last_run TIMESTAMP WITH TIME ZONE DEFAULT '1000-01-01'::TIMESTAMPTZ
        )
    };
    $dbh->do($sql);
    logmsg("INFO", "Ensured libraryiq.history table exists");
}

1;