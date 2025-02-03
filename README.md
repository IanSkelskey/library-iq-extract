# Evergreen LibraryIQ Export

This software extracts data from an Evergreen server and securely transfers the output to a specified SFTP server. It also sends an email notification upon completion, indicating success or failure. The output data is stored locally in a specified archive folder.

## Features

- **Modular Design**: The script is divided into multiple modules for better maintainability and readability.
- **Chunking Data**: Large queries are processed in chunks to prevent memory consumption and timeouts.
- **Email Notifications**: Notifies staff of success or failure, including logs or summaries.
- **SFTP Transfer**: Securely uploads results to a remote server.
- **Logging**: Verbose logging to track the execution process and any errors.
- **History Tracking**: Stores the last run time to determine whether to run a partial (incremental) or full extract.

## Directory Structure

```
📁 config/
    └── ⚙️ library_config.conf.example
📁 lib/
    ├── 🐪 DB.pm
    ├── 🐪 Email.pm
    ├── 🐪 Logging.pm
    ├── 🐪 Queries.pm
    ├── 🐪 SFTP.pm
    └── 🐪 Utils.pm
📄 .gitignore
🐪 extract_libraryiq.pl
📄 README.md
```

## Installation

1. Clone the repository:
    ```bash
    git clone https://github.com/IanSkelskey/library-iq-extract.git
    cd evergreen-libraryiq-export
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

- `logfile`: Path to the log file.
- `tempdir`: Temporary directory for storing intermediate files.
- `archive`: Directory for storing archived files.
- `libraryname`: Comma-separated list of branch/system shortnames.
- `chunksize`: Number of records to process per chunk.
- `ftphost`, `ftplogin`, `ftppass`, `remote_directory`: SFTP server details.
- `alwaysemail`, `fromemail`, `erroremaillist`, `successemaillist`: Email notification settings.

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

### Command Line Options

- `--config`: Path to the configuration file (default: library_config.conf).
- `--debug`: Enable debug mode for more verbose output.
- `--full`: Perform a full dataset extraction.
- `--no-email`: Disable email notifications.
- `--no-sftp`: Disable SFTP file transfer.

## Modules

- **DB.pm**: Handles database connections and chunked queries.
- **Email.pm**: Handles email notifications.
- **Logging.pm**: Handles logging with timestamps.
- **Queries.pm**: Contains SQL queries for fetching data.
- **SFTP.pm**: Handles SFTP file transfers.
- **Utils.pm**: Contains utility functions for reading configuration, tracking history, and processing data types.

## Example Workflow

1. **Parse Config & CLI**: The script reads the configuration file and command-line options.
2. **DB Connection**: Establishes a connection to the PostgreSQL database.
3. **Determine Run Mode**: Checks the last run time to decide between full or incremental extraction.
4. **Process Data Types**: For each data type (BIBs, Items, Circs, Patrons, Holds), it:
    - Retrieves IDs in chunks.
    - Fetches details for each chunk.
    - Writes data to a file.
5. **Update History**: Marks the last run time in the database.
6. **SFTP Upload & Email**: Uploads the output files via SFTP and sends an email notification.

## License

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
