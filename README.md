OshiUpload is a powerful anonymous public file sharing FLOSS, its advantages are:

* Respects users privacy - no logs are collected
* Command-line uploads via PUT method (curl -T)
* TCP uploads via netcat and telnet
* Manage interface for each upload
* Optional instant destruction after download
* User defined expiry time
* Simple administration interface
* Easy template along with a _very stylish no-JavaScript_ version included
* Duplicate files detection using SHA* sums

This is a synced source code we are currently running at [oshi.at](https://oshi.at)

The interface design is influenced by mixtape.moe and transfer.sh

Our admin interface only provides general stats, abuse reports and a file finder by URL. Unlike all popular file sharing platforms, it doesn't provide a possibility of live tracking/viewing uploaded files in order to avoid attracting unnecessary enthusiasm (self-restriction is good). 

The duplicate files detection feature allows to create links to existing files in case the uploaded file already exists on the storage, this helps to save a lot of space. This feature is awesome and it's the main reason why we store hash sums. We compare file size, mimetype and hashsum prior to creating link to ensure absence of collisions. In case the origin file is about to expire or get deleted but it has links, one of the links becomes a new origin (one with a longest retention period).

# Installing & Running

### Prepare

`git clone https://github.com/somenonymous/OshiUpload`

`cd OshiUpload/app`

rename `config.example` to `config` and configure it following the options described in comments

The engine will create all the necessary database tables automatically on the first run


### Install dependencies

Debian/Ubuntu

```
apt install libmojolicious-perl libdbix-connector-perl libtry-tiny-perl liburi-encode-perl libdata-random-perl libstring-random-perl libgd-securityimage-perl libjavascript-minifier-perl libfile-libmagic-perl libclamav-client-perl
apt install libdbd-sqlite3-perl # for SQLite as database
apt install libdbd-mysql-perl # for MySQL/MariaDB as database
```

CPAN or perlbrew

```
cpan -i Mojolicious DBIx::Connector Try::Tiny URI::Encode Data::Random String::Random GD::SecurityImage JavaScript::Minifier File::LibMagic ClamAV::Client
cpan -i DBD::SQLite # for SQLite as database
cpan -i DBD::mysql # for MySQL/MariaDB as database
```

If you want to install modules as non-root, substitute `cpan` with `cpanm` from `perlbrew` (get it on [https://perlbrew.pl](https://perlbrew.pl) if your distro doesn't ship the `perlbrew` package)


### Run
`./oshi_run.pl`

or just add tools/cron.sh to _/etc/crontab_ so the engine will autorun:

`* * * * *	nobody	/full/path/to/OshiUpload/tools/cron.sh > /dev/null 2>&1`
