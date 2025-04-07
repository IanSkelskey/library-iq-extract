# Evergreen LibraryIQ Export

This software extracts data from an Evergreen server and securely transfers the output to a specified SFTP server. It also sends an email notification upon completion, indicating success or failure. The output data is stored locally in a specified archive folder.

![Perl](https://img.shields.io/badge/Perl-39457E?style=for-the-badge&logo=perl&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-336791?style=for-the-badge&logo=postgresql&logoColor=white)

## Features

- **Modular Design**: The script is divided into multiple modules for better maintainability and readability.
- **Chunking Data**: Large queries are processed in chunks to prevent memory consumption and timeouts.
- **Email Notifications**: Notifies staff of success or failure, including logs or summaries.
- **SFTP Transfer**: Securely uploads results to a remote server.
- **Logging**: Verbose logging to track the execution process and any errors.
- **History Tracking**: Stores the last run time to determine whether to run a partial (incremental) or full extract.

## Directory Structure

```
📁 archive/
    ├── 📄 .gitkeep
📁 config/
    └── ⚙️ library_config.conf.example
📁 lib/
    ├── 🐪 DBUtils.pm
    ├── 🐪 Email.pm
    ├── 🐪 Logging.pm   
    ├── 🐪 Queries.pm
    ├── 🐪 SFTP.pm
    └── 🐪 Utils.pm
📁 tmp/
    ├── 📄 .gitkeep
📄 .gitignore
🐪 email_test.pl
🐪 sftp_test.pl
🐪 extract_libraryiq.pl
📄 README.md
```

## Installation

1. Clone the repository:
    ```bash
    git clone https://github.com/IanSkelskey/library-iq-extract.git
    cd libraryiq-extract
    ```

2. Copy the example configuration file and edit it to match your environment:
    ```bash
    cp config/library_config.conf.example config/library_config.conf
    vi config/library_config.conf
    ```

3. Install the required Perl modules:
    ```bash
    cpan install DBI DBD::Pg Net::SFTP::Foreign Email::MIME Email::Sender::Simple
    ```

## Configuration

Edit the `config/library_config.conf` file to set the appropriate values for your environment. Key configuration options include:

| Configuration Option | Description                                                   |
| -------------------- | ------------------------------------------------------------- |
| `logfile`            | Path to the log file.                                         |
| `tempdir`            | Temporary directory for storing intermediate files.           |
| `archive`            | Directory for storing archived files.                         |
| `cleanup`            | Whether to clean up the archive directory.                    |
| `diff_overlap_days`  | Number of days to overlap when calculating incremental data.  |
| `librarynames`       | Comma-separated list of branch/system shortnames.             |
| `chunksize`          | Number of records to process per chunk.                       |
| `ftphost`            | SFTP server hostname.                                         |
| `ftplogin`           | SFTP server login username.                                   |
| `ftppass`            | SFTP server login password.                                   |
| `remote_directory`   | Directory on the SFTP server where files will be uploaded.    |
| `alwaysemail`        | Always send email notifications, even if there are no errors. |
| `fromemail`          | Email address from which notifications will be sent.          |
| `erroremaillist`     | Comma-separated list of email addresses to notify on error.   |
| `successemaillist`   | Comma-separated list of email addresses to notify on success. |

## Usage

Make sure the script has execute permissions:

```bash
chmod +x extract_libraryiq.pl
```

Run the script with the desired options:

```bash
./extract_libraryiq.pl --config config/library_config.conf
```

Run the script without any network operations (email, SFTP):

```bash
./extract_libraryiq.pl --config config/library_config.conf --no-email --no-sftp
```

A common configuration I used for testing with libraryiq:

```bash
./extract_libraryiq.pl --config config/library_config.conf --full --debug --no-update-history
```

### Command Line Options

| Option                | Description                                                    |
| --------------------- | -------------------------------------------------------------- |
| `--config`            | Path to the configuration file (default: library_config.conf). |
| `--debug`             | Enable debug mode for more verbose output.                     |
| `--full`              | Perform a full dataset extraction.                             |
| `--no-email`          | Disable email notifications.                                   |
| `--no-sftp`           | Disable SFTP file transfer.                                    |
| `--drop-history`      | Drop and recreate the libraryiq schema before running.         |
| `--no-update-history` | Do not update the last run time in the history table.          |

## Perl Modules

| Module         | Description                                                                                        |
| -------------- | -------------------------------------------------------------------------------------------------- |
| **DB.pm**      | Handles database connections and chunked queries.                                                  |
| **Email.pm**   | Handles email notifications.                                                                       |
| **Logging.pm** | Handles logging with timestamps.                                                                   |
| **Queries.pm** | Contains SQL queries for fetching data.                                                            |
| **SFTP.pm**    | Handles SFTP file transfers.                                                                       |
| **Utils.pm**   | Contains utility functions for reading configuration, tracking history, and processing data types. |

## Process Flow

```mermaid
flowchart LR
    A[Start] --> B[Setup]
    B --> C[Process Data]
    C --> D[Create tar.gz Archive]
    D --> E[Send Email Notification]
    E --> F[Update Last Run Time & Cleanup]
    F --> G[Finish]
```

## Cleanup Strategy

The script includes a robust cleanup strategy to manage the files generated during its execution. This ensures that disk space is conserved and only the most relevant files are retained.

### Files Created

1. **Temporary Files**:
   - Intermediate files (e.g., TSV files) are created in the directory specified by the `tempdir` configuration option.
   - These files are used during the processing of data and are deleted after the script completes.

2. **Archived Files**:
   - Final output files (e.g., compressed `.tar.gz` archives or raw `.tsv` files) are stored in the directory specified by the `archive` configuration option.
   - These files are retained for future reference or manual re-upload if needed.

### Cleanup Process

1. **Temporary Directory (`tempdir`)**:
   - All files in the `tempdir` are deleted after the script completes, regardless of success or failure.
   - This ensures that the temporary directory is always empty after the script runs.

2. **Archive Directory (`archive`)**:
   - The script retains only the most recent **full extract** and the most recent **diff extract** in the archive directory.
   - Older files are automatically deleted to conserve disk space.

### Warning: Temporary Directory Deletion

**Important**: The directory specified in the `tempdir` configuration is completely emptied after every run of the script. This means that **all files in this directory will be deleted**, regardless of whether they were created by the script or not.

To avoid accidental data loss:
- Leave the `tempdir` configuration as the default relative directory (`tmp`).
- If you need to change it, ensure that the directory is dedicated solely to this script's temporary files.

### Example Configuration

Here is an example configuration for the `tempdir` and `archive` options:

```plaintext
tempdir = tmp
archive = archive
```

- `tempdir`: Temporary files will be stored in the `tmp` directory relative to the script's location.
- `archive`: Final output files will be stored in the `archive` directory relative to the script's location.

If you need to use absolute paths, ensure that the `tempdir` points to a dedicated directory:

```plaintext
tempdir = /path/to/dedicated/tempdir
archive = /path/to/archive
```

## Setting Up Cron Jobs

To automate the extraction process, you can set up cron jobs to run the script at specified intervals. For example, you can run a full extract once per month and an incremental extract nightly.

1. Open the crontab file for editing:
    ```bash
    crontab -e
    ```

2. Add the following lines to schedule the full extract to run at 2 AM on the first day of every month and the incremental extract to run at 2 AM every night:

    ```bash
    # Full extract on the first day of every month at 2 AM
    0 2 1 * * /path/to/extract_libraryiq.pl --config /path/to/config/library_config.conf --full

    # Incremental extract every night at 2 AM
    0 2 * * * /path/to/extract_libraryiq.pl --config /path/to/config/library_config.conf
    ```

    Replace `/path/to/extract_libraryiq.pl` and `/path/to/config/library_config.conf` with the actual paths to your script and configuration file.

3. Save and close the crontab file.

These cron jobs will ensure that the full extract runs once a month and the incremental extract runs nightly, automating the data extraction process.
