package OshiUpload;

use feature 'say';
use strict;
use warnings;
use File::LibMagic;
use Digest::SHA qw/sha1_hex sha256_hex/;
use Data::Random qw(:all);
use String::Random;
use URI::Encode qw(uri_encode uri_decode);
use Time::HiRes;
use DBIx::Connector;
use Try::Tiny;
use Scalar::Util qw/looks_like_number/;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::URL;

sub new {
 my($class, %o) = @_;
 
 my $self = bless({}, $class);
 
 my $configpath = exists $o{configpath} ? $o{configpath} : "config";

 $self->load_config($configpath);
 $self->checkups;

 $self->{ShortURL} = new String::Random;
 $self->{ShortURL}->{'X'} = [qw/a b c d e f g h i j k m n o p q r s t u v w x y z A B C D E F G H J K L M N P Q R S T U V W X Y Z/];

 $self->{libmagic} = File::LibMagic->new();

 if ( $self->{conf}->{CLAMAV_SCANS_ENABLED} ) {

	require ClamAV::Client;
	$self->{clamav} = ClamAV::Client->new();

 }

 return $self;
}

sub template_vars {
	my $self = shift;
	my $g = {
		FILE_HASH_TYPE => $self->{conf}->{UPLOAD_TRACK_DUPLICATES_HASHTYPE},
		MAX_FILE_SIZE => $self->{conf}->{HTTP_UPLOAD_FILE_MAX_SIZE},
		MAX_FILE_SIZE_TCP => $self->{conf}->{TCP_UPLOAD_FILE_MAX_SIZE},
		MAIN_DOMAIN => $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}},
		MAIN_DOMAIN_PROTO => $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN} . '_PROTO'},
		CDN_DOMAIN => $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_CDN'},
		CDN_DOMAIN_PROTO => $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_CDN_PROTO'},
		DIRECT_DOMAIN => $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET'},
		DIRECT_DOMAIN_PROTO => $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_PROTO'},
		ONION_DOMAIN => $self->{conf}->{UPLOAD_DOMAIN_ONION},
		ONION_DOMAIN_PROTO => $self->{conf}->{UPLOAD_DOMAIN_ONION_PROTO},
		TCP_DOMAIN => $self->{conf}->{UPLOAD_DOMAIN_TCP},
		TCP_PORT_RAW => $self->{conf}->{TCP_RAW_PORT},
		TCP_PORT_BASE64 => $self->{conf}->{TCP_BASE64_PORT},
		TCP_PORT_HEX => $self->{conf}->{TCP_HEX_PORT},
		MANAGE_ROUTE => $self->{conf}->{UPLOAD_MANAGE_ROUTE},
		USE_HTTP_HOST => $self->{conf}->{UPLOAD_LINK_USE_HOST},
		INSECUREPATH => $self->{conf}->{HTTP_INSECUREPATH},
		ABUSE_CAPTCHA_REQUIRED => $self->{conf}->{CAPTCHA_SHOW_FOR_ABUSE},
		HASHSUMS_ENABLED => $self->{conf}->{UPLOAD_HASH_CALCULATION},
		DOWNLOAD_LIMIT_PER_FILE => $self->{conf}->{DOWNLOAD_LIMIT_PER_FILE}
	};

	return $g;
}

sub textonly_output {
	my ($self, $path, $mpath, $customhost) = @_;

	my $currenturl = defined $customhost ? $customhost : $self->{MAIN_DOMAIN_PROTO} . '://' .  $self->{MAIN_DOMAIN};
	my $currenthost = Mojo::URL->new($currenturl)->host_port;

	my $str = $currenturl . $self->{conf}->{UPLOAD_MANAGE_ROUTE} . $mpath . " [Admin]\r\n";
			  
	$str .= $currenturl . '/' . $path . " [Download]\r\n";
	
	if ( $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'ALL' or $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'UPLOAD_DOMAIN_CLEARNET_CDN' )
	{
		$str .= $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_CDN_PROTO'} . '://' . 
			$self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_CDN'} . '/' . $path . " [CDN download]\r\n"
			if exists $self->{conf}->{UPLOAD_DOMAIN_CLEARNET_CDN} and $self->{conf}->{UPLOAD_DOMAIN_CLEARNET_CDN} ne $currenthost
	}

	if ( $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'ALL' or $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'UPLOAD_DOMAIN_CLEARNET' )
	{
		$str .= $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_PROTO'} . '://' . 
			$self->{conf}->{'UPLOAD_DOMAIN_CLEARNET'} . '/' . $path . " [Direct IP download]\r\n"
			if exists $self->{conf}->{UPLOAD_DOMAIN_CLEARNET} and $self->{conf}->{UPLOAD_DOMAIN_CLEARNET} ne $currenthost
	}

	if ( $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'ALL' or $self->{conf}->{UPLOAD_DOMAINS_ENABLED} eq 'UPLOAD_DOMAIN_ONION' )
	{
		$str .= $self->{conf}->{'UPLOAD_DOMAIN_ONION_PROTO'} . '://' . 
			$self->{conf}->{'UPLOAD_DOMAIN_ONION'} . '/' . $path . " [Tor download]\r\n"
			if exists $self->{conf}->{UPLOAD_DOMAIN_ONION} and $self->{conf}->{UPLOAD_DOMAIN_ONION} ne $currenthost
	}
	
	return $str;
}

sub checkups {
	my $self = shift;
	# todo: move to YAML
	die "UPLOAD_FILENAME_MAX_LENGTH is not defined" unless exists $self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH};
	die "UPLOAD_DOMAIN_MAIN is not defined" unless exists $self->{conf}->{UPLOAD_DOMAIN_MAIN};
	die $self->{conf}->{UPLOAD_DOMAIN_MAIN} . " is not defined" unless exists $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}};
	die "UPLOAD_STORAGE_PATH is not defined" unless exists $self->{conf}->{UPLOAD_STORAGE_PATH};

	$self->{MAIN_DOMAIN} = $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}};
	$self->{MAIN_DOMAIN_PROTO} = $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN} . '_PROTO'};
	$self->{conf}->{UPLOAD_STORAGE_PATH} .= '/' unless $self->{conf}->{UPLOAD_STORAGE_PATH} =~ /\/$/;
	$self->{conf}->{UPLOAD_STORAGE_PATH} =~ s/[\/]+/\//g;

	$self->{conf}->{MODULES_AUTOSTART} = 1 unless exists $self->{conf}->{MODULES_AUTOSTART};
	$self->{conf}->{CONTENT_VIEW_UNTIL_SIZE} = 2000000 unless exists $self->{conf}->{CONTENT_VIEW_UNTIL_SIZE};
	$self->{conf}->{HTTP_INSECUREPATH} = 'insecure' unless exists $self->{conf}->{HTTP_INSECUREPATH};
	$self->{conf}->{HTTP_INSECUREPATH} =~ s/[\/]+/\//g;
	$self->{conf}->{UPLOAD_DOMAIN_TCP} = $self->{MAIN_DOMAIN} unless exists $self->{conf}->{UPLOAD_DOMAIN_TCP};
	$self->{conf}->{UPLOAD_FILE_PERMISSIONS} =  exists $self->{conf}->{UPLOAD_FILE_PERMISSIONS} ? oct $self->{conf}->{UPLOAD_FILE_PERMISSIONS} : 0440;
	$self->{conf}->{CLAMAV_SCANS_ENABLED} = exists $self->{conf}->{CLAMAV_SCANS_ENABLED} ? int $self->{conf}->{CLAMAV_SCANS_ENABLED} : 0;
	$self->{conf}->{CLAMAV_SCANS_LOG} = undef unless exists $self->{conf}->{CLAMAV_SCANS_LOG};
	$self->{conf}->{UPLOAD_HASH_CALCULATION} = exists $self->{conf}->{UPLOAD_HASH_CALCULATION} ? int $self->{conf}->{UPLOAD_HASH_CALCULATION} : 1;
	$self->{conf}->{TCP_RAW_ADDRESS} = '127.0.0.1' unless exists $self->{conf}->{TCP_RAW_ADDRESS};
	$self->{conf}->{TCP_BASE64_ADDRESS} = '127.0.0.1' unless exists $self->{conf}->{TCP_BASE64_ADDRESS};
	$self->{conf}->{TCP_HEX_ADDRESS} = '127.0.0.1' unless exists $self->{conf}->{TCP_HEX_ADDRESS};
	$self->{conf}->{TCP_RAW_PORT} = 7777 unless exists $self->{conf}->{TCP_RAW_PORT};
	$self->{conf}->{TCP_BASE64_PORT} = 7778 unless exists $self->{conf}->{TCP_BASE64_PORT};
	$self->{conf}->{TCP_HEX_PORT} = 7779 unless exists $self->{conf}->{TCP_HEX_PORT};
	$self->{conf}->{DOWNLOAD_LIMIT_PER_FILE} = 0 unless exists $self->{conf}->{DOWNLOAD_LIMIT_PER_FILE};

	$self->{MIMETYPE_SIZE_LIMITS} = {};
	
	try {
		$self->{MIMETYPE_SIZE_LIMITS} =  decode_json $self->{conf}->{CONTENT_VIEW_UNTIL_SIZE};
	} catch {
		say '[error] decoding JSON from CONTENT_VIEW_UNTIL_SIZE failed: ' . $_;
		say 'The format description can be found in config.example';
	};

	$self->{SHORTURLMINLEN} = exists $self->{conf}->{SHORTURL_LENGTH}?int $self->{conf}->{SHORTURL_LENGTH}:5;
	$self->{SHORTURLMAXLEN} = 16;
	$self->{FNMAXLEN} = exists $self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH}?$self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH}:100;
	$self->{FNMAXLEN} -= $self->{SHORTURLMAXLEN}; 
	$self->{HASHTYPE} = exists $self->{conf}->{UPLOAD_TRACK_DUPLICATES_HASHTYPE}?$self->{conf}->{UPLOAD_TRACK_DUPLICATES_HASHTYPE}:1;
	$self->{CAPTCHA_TOKEN_TIME} = exists $self->{conf}->{CAPTCHA_TOKEN_EXPIRE_TIME} ? $self->{conf}->{CAPTCHA_TOKEN_EXPIRE_TIME} : 300;
	$self->{CAPTCHA_TOKEN_TIME} = 300 if int $self->{CAPTCHA_TOKEN_TIME} < 1;
	$self->{RESTRICTED_FILE_TYPES} = exists $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_TYPES} ? [split (/\s+/, $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_TYPES})] : [];
	$self->{RESTRICTED_FILE_EXTENSIONS} = exists $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_EXTENSIONS} ? [split (/\s+/, $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_EXTENSIONS})] : [];
	$self->{RESTRICTED_FILE_HITLIMIT} = exists $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_AFTER_HITS} ? int $self->{conf}->{UPLOAD_FORCE_DESTROYONDL_AFTER_HITS} : 1;
	$self->{CLAMAV_FILE_TYPES} = exists $self->{conf}->{CLAMAV_SCANS_TYPES} ? [split (/\s+/, $self->{conf}->{CLAMAV_SCANS_TYPES})] : [];

}

sub newfilename {
	my $self = shift;
	my $type = shift || '';
	my $filename = shift || '';
	
	if ( $type eq 'manage' ) {
		my $randomstr = rand_chars ( set => 'alpha', min => 10, max => 20 );
		return sha1_hex(Time::HiRes::time . $randomstr);
	}
	elsif ( $type eq 'random' ) {
		my $ext = '';
		$ext = $1 if $filename =~ /(\.[^\s\.]+)$/;
		return rand_chars ( set => 'alpha', min => 4, max => 4 ) . $ext;
	}
	
	my $randomname = $self->{ShortURL}->randpattern("X" x $self->{SHORTURLMINLEN});
	
	my $try = 0;
	while ( $try < 5) {
		$try++;
		if ( $self->db_get_row('uploads', 'urlpath', $randomname) ) {
			say '[info] Duplicate generated, adding random char to "' . $randomname . '"' if $self->{conf}->{DEBUG} > 0;
			$randomname .= $self->{ShortURL}->randpattern("X");
		} else { $try = 5 }
	}
	return $randomname;
}

sub process_file {
	my $self = shift;
	my $proto = shift;
	my $mpath = shift;
	my $storage = shift;
	my $url = shift;
	my $filename = shift;
	my $size = shift;
	my $shorturl = shift || 0;
	my $expire = shift;
	my $destroyafterload = shift || 0;
	my $destroyafterload_locked = 0;
	
	my $file = $self->build_filepath($storage,$url,$filename);
	
	if ( defined $expire && $expire == 0 ) {
		$expire = 0;
	}elsif ( !$expire ) {
		$expire = $self->{conf}->{UPLOAD_TIME_DEFAULT}
	}

	my $isdup = 0;
	my $type = 'file';
	my $linktarget;
	my $link = '';
	
	chmod $self->{conf}->{UPLOAD_FILE_PERMISSIONS}, $file;
	
	if ( $self->db_get_row('uploads', 'urlpath', $url) ) {
		die "URL already exists in DB ($url)\n";
		### check newfilename() if this is still an issue
=cut
		my $oldfile = $file;
		$url = substr($mpath,0,5) . $url;
		$isdup = 1;
		$file = $self->build_filepath($storage,$url,$filename);
		if ( -f $file ) {
			# this is a fatal condition
			die('Found a duplicate after a found duplicate in DB: ' . $file);
		}
		rename ($oldfile, $file) or die($!);
=cut
	}

	$self->{dbc}->run(sub {
		my $dbh = shift;
		$dbh->do("insert into uploads (mpath, urlpath, processing) values (?,?,1)", undef, $mpath, $url);
	});

	my $hash  =  '';
	my $ftype;
	try { $ftype = $self->{libmagic}->info_from_filename($file)->{mime_type} };
	$ftype = 'unknown/unknown' if length($ftype) < 2;
	$ftype = substr($ftype,0,32);

	# try { utf8::decode($filename) };
	
	# enforce "Destroy after download" in case there is match against UPLOAD_FORCE_DESTROYONDL_TYPES / UPLOAD_FORCE_DESTROYONDL_EXTENSIONS
	if	( (grep { $ftype eq lc $_ } @{$self->{RESTRICTED_FILE_TYPES}}) || (grep { $filename =~ /\.\Q$_\E\s*$/i } @{$self->{RESTRICTED_FILE_EXTENSIONS}}) )
	{
		$destroyafterload = 1;
		$destroyafterload_locked = 1;
	}

	my $still_processing = $self->{conf}->{UPLOAD_HASH_CALCULATION} ? 1 : 0;
	my @values = (	$mpath, $url, $storage, $filename, $type, $hash, $ftype, $link, int $shorturl,
					time, ( $expire == 0 ? 0 : (time+($expire*60)) ), $destroyafterload, $destroyafterload_locked, $isdup, $proto, $size, 0, $still_processing	);
	
	$self->{dbc}->run(sub {
		my $dbh = shift;
		$dbh->do("replace into uploads values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,0,0)", undef, @values);
	});

    say "[info] process_file() finished ($mpath)" if $self->{conf}->{DEBUG} > 1;
	
}

sub process_file_hashsum {
	my $self = shift;
	#my $urlpath = shift;
	my $mpath = shift;

	#my $row = $self->db_get_row('uploads', 'urlpath', $urlpath);
	my $row = $self->db_get_row('uploads', 'mpath', $mpath);
	
	die "process_file_hashsum: record not found for $mpath" unless $row;
	die "process_file_hashsum: already processed ($mpath)" if !$row->{'processing'};
	
	my $file = $self->build_filepath( $row->{'storage'},$row->{'urlpath'},$row->{'rpath'} );
	
	my $fh;
	unless (open $fh, $file) {
		die "process_file_hashsum: open $file: $!";
	}

	$self->{dbc}->run(sub { $_->do("update uploads set processing = 2 where mpath = ?", undef, $row->{'mpath'}) });

	my $sha = Digest::SHA->new($self->{HASHTYPE});
	$sha->addfile($fh);
	my $hash = $sha->hexdigest;
	close $fh;

	$self->{dbc}->run(sub { $_->do("update uploads set hashsum = ? where mpath = ?", undef, $hash, $row->{'mpath'}) });

	if ( exists $self->{conf}->{UPLOAD_TRACK_DUPLICATES} && $self->{conf}->{UPLOAD_TRACK_DUPLICATES} == 1 )
	{
		my $hashexists;
		$self->{dbc}->run(sub {
			$hashexists = $_->selectrow_hashref("SELECT * FROM uploads WHERE hashsum = ? and mpath != ? and type = 'file' and ( expires = 0 or expires > ? ) LIMIT 1", undef, $hash, $row->{'mpath'}, (time + 300));
		});
		if ( $hashexists ) {
			say '[info] Duplicate file exists with the same hash (' . $row->{'mpath'} . ')' if $self->{conf}->{DEBUG} > 1;

			# only make link if expire time is more than 5 minutes from now or file never expire (0)
			if ( ($hashexists->{expires} - time) > 300 || $hashexists->{expires} == 0 ) {
				if ( $row->{'ftype'} eq $hashexists->{ftype} and $row->{'size'} == $hashexists->{size} ) {
					say '[info] Creating link (' . $row->{'mpath'} . ')' if $self->{conf}->{DEBUG} > 1;
					
					my $link = $self->build_filepath($hashexists->{storage},$hashexists->{urlpath},$hashexists->{rpath});
					if ( -f $link  ) {
						unlink $file;
						$self->{dbc}->run(sub { $_->do("update uploads set type = ?, link = ? where mpath = ?", undef, 'link', $link, $row->{'mpath'}) });
					} else {
						say '[warn] Tried to create a link, but target file "' . $file . '" does not exist (' . $row->{'mpath'} . ')' if $self->{conf}->{DEBUG} > 0;
					}
				}
			}
		}
	}
	
	$self->{dbc}->run(sub { $_->do("update uploads set processing = 0 where mpath = ?", undef, $row->{'mpath'}) });
}

sub process_unfinished_hashsum {
	# process unfinished hashsum calculations, usually due to unstarted process_file_hashsum() because of periodic graceful restarts in Mojo::Server::Prefork (->accepts)
	# run only when no other process_file_hashsum() are working to not overlap with queues
	my $self = shift;

	my $mpath = $self->{dbc}->dbh->selectrow_array('select mpath from uploads where processing = 1 and created < ? and type = "file" order by created limit 1', undef, (time - 60));
	
	return unless $mpath;

	my $running = $self->{dbc}->dbh->selectrow_array('select count(*) from uploads where processing = 2');
	# say 'Running process_file_hashsum(): ' . $running;
	die "process_unfinished_hashsum: other calculations ongoing" if $running;
	
	say('[info] started process_unfinished_hashsum for ' . $mpath) if $self->{conf}->{DEBUG} > 0;
	$self->process_file_hashsum($mpath);
	say('[info] finished process_unfinished_hashsum for ' . $mpath) if $self->{conf}->{DEBUG} > 0;
}

sub build_url {
	my $self = shift;
	my $type = shift || '';
	my $url = shift;
	my $baseurl = shift || 'UPLOAD_DOMAIN_MAIN';
	my $burl = $baseurl;
	$burl = $self->{conf}->{$baseurl . '_PROTO'} . '://' . $self->{conf}->{$baseurl} if $baseurl =~ /^UPLOAD_DOMAIN/;
	$burl = $self->{conf}->{$self->{conf}->{'UPLOAD_DOMAIN_MAIN'} . '_PROTO'} . '://' . $self->{conf}->{$self->{conf}->{$baseurl}}
			  if $baseurl eq 'UPLOAD_DOMAIN_MAIN';
	return  $burl .
			$self->{conf}->{UPLOAD_MANAGE_ROUTE} . $url if $type eq 'manage';
	return  $burl . '/' . $url;
}

sub build_filepath {
	my ($self, $storage, $url, $filename) = @_;
	my $filepath = $storage . $url . '_' . $filename;
	#try { utf8::decode($filepath) };
	return $filepath;
}

sub get_file {
	my ($self, $select_by, $id) = @_;
	if ( $select_by eq 'mpath' ) {
			$id =~ s/[^a-zA-Z0-9]//g;
			return $self->db_get_row('uploads', 'mpath', $id);
	}  elsif( $select_by eq 'urlpath' ) {
			$id =~ s/[^a-zA-Z0-9]//g;
			return $self->db_get_row('uploads', 'urlpath', $id);
	}elsif( $select_by eq 'url' ) {
			$id =~ s/^[^\/]*https?\:\/\///i;
			$id =~ s/^[^\/]*\///;
			if ( $id =~ /^([a-zA-Z0-9]+)/ ) {
				$id =~ $1;
				return $self->db_get_row('uploads', 'urlpath', $id);
			}
	}
	return undef;
}

sub delete_file {
	my ($self, $select_by, $id, $runmode) = @_;
	$self->delete_file_job( $select_by, $id );
}

sub delete_file_job {
	my ($self, $select_by, $id) = @_;
		try {
			my $row = $self->db_get_row('uploads',  $select_by, $id);
			return $row unless $row;

			if ( $row->{'type'} eq 'file' ) {
				my $file = $self->build_filepath( $row->{'storage'},$row->{'urlpath'},$row->{'rpath'} );
				
				my $hashexists;
				$self->{dbc}->run(sub {
					my $dbh = shift;
					$hashexists = $dbh->selectrow_hashref("SELECT * FROM uploads WHERE hashsum = ? and type = 'link' LIMIT 1", undef, $row->{'hashsum'});
				});

				if ( $hashexists ) {
					my $newfile = $self->build_filepath( $hashexists->{'storage'},$hashexists->{'urlpath'},$hashexists->{'rpath'} );
					rename ($file,$newfile);
					$self->{dbc}->run(sub {
							my $dbh = shift;
							$dbh->do("update uploads set link=? where hashsum = ?", undef, $newfile, $hashexists->{'hashsum'} );
					});
					$self->{dbc}->run(sub {
							my $dbh = shift;
							$dbh->do("update uploads set type = 'file',link='' where mpath = ?", undef, $hashexists->{'mpath'} );
					});

				} else {
					unlink $file;
				}
			}

			$self->{dbc}->run(sub {
				$_->do("delete from uploads where $select_by = ?", undef, $id);
			});
		} catch {
			say '[info] Error deleting file: ' . $_ if $self->{conf}->{DEBUG} > 0;
		};
			
}

sub expiry_check {
	my ($self, $new_expire, $stored_expire) = @_;

	if ( int $new_expire == 0 && $self->{conf}->{UPLOAD_TIME_MAX} > 0 ) {
		return (0,"Lifetime uploads are disabled, you must specify expiry time (max: " . $self->{conf}->{UPLOAD_TIME_MAX} . " minutes)")
	}
	if ( int $new_expire < $self->{conf}->{UPLOAD_TIME_MIN} ) {
		return (0,"Expiry time can't be less than " . $self->{conf}->{UPLOAD_TIME_MIN} . " minutes")
	}
	if ( int $new_expire < 0 ) {
		return (0,"Expiry time can't be less than zero")
	}
	if ( int $new_expire > $self->{conf}->{UPLOAD_TIME_MAX} ) {
		return (0,"Expiry time can't be greater than " . $self->{conf}->{UPLOAD_TIME_MAX} . " minutes")
	}
	if ( $stored_expire && (time+($new_expire*60)) < $stored_expire ) {
		return (0,"Expiry time can't be before " . (scalar localtime $stored_expire))
	}
	return 1;
}

sub filename_check {
	my ($self, $filename) = @_;
	use bytes;

	if ( bytes::length($filename) > $self->{FNMAXLEN} ) {
		return (0,"Filename is too big, max: " . $self->{FNMAXLEN})
	}

	return 1;
	
}

sub load_config {
	my $self = shift;
	my $path = shift;
	
	$self->{conf} = {};
	open my $f, '<', $path or die $!;
	while (<$f>) {
		my $line = $_;
		if ( $line =~ /^\s*([^\s\#]+)\s*=\s*(.*)/ ){
			$self->{conf}->{$1} = trim($2) 
		}
	}
	close $f;
}

sub trim {
    (my $s = $_[0]) =~ s/^\s+|\s+$//g;
    return $s;
}

sub parse_filename {
	my $self = shift;
	my $s = shift;
    #$s =~ s/[^0-9a-zA-Z_\.\-\^\,\s\%]//g;
    $s =~ s/[\\\/\;\:\*\?\"\<\>\|]//g;
    $s =~ s/[^[:print:]]//g;
    $s = uri_decode($s);
    $s =~ s/\s/_/g;
    try { utf8::encode($s) };
    return $s;
}

sub db_get_row {
	my $self = shift;
	my $table = shift;
	my $what = shift;
	my $value = shift;
	my $r;
	$self->{dbc}->run(sub {
		my $dbh = shift;
		$r = $dbh->selectrow_hashref("SELECT * FROM $table WHERE $what = ? LIMIT 1", undef, $value);
	});
	return $r;
}

sub db_init {
	my $self = shift;
	
	my $type = lc $self->{conf}->{DB_TYPE} eq 'mysql' ? 'mysql:database=' : 'SQLite:dbname=';
	my $str = "dbi:$type" . $self->{conf}->{DB_NAME};
	$str .= ';host=' . $self->{conf}->{DB_HOST} if exists $self->{conf}->{DB_HOST};
	$str .= ';port=' . $self->{conf}->{DB_PORT} if exists $self->{conf}->{DB_PORT};

	$self->{'dbc'} = DBIx::Connector->new($str, $self->{conf}->{DB_USER}, $self->{conf}->{DB_PASS}, 
	 {    RaiseError => 1, 
		  PrintWarn  => 1, 
		  PrintError => 0, 
		  AutoCommit => 1, 
		  ## mysql_enable_utf8 => 1  ##
		  ### TO FIX: when disabled, filenames appear in wrong charset in MySQL, but turned on breaks downloads with utf8 symbols
	 });
	$self->{'dbc'}->dbh or die("Could not connect to the DB: " . $!);
	$self->{'dbc'}->mode('fixup');
	
	
	$self->db_struct;
	$self->db_parse_struct;
	$self->db_check_tables;
	return $self;
}


sub db_struct {
	my $self = shift;
	my $t = lc $self->{conf}->{DB_TYPE};
	die "FNMAXLEN not defined" unless exists $self->{FNMAXLEN};
	die "HASHTYPE not defined" unless exists $self->{HASHTYPE};
	my %hlen = (1 => 40, 224 => 56, 256 => 64, 384 => 96, 512 => 128);
	my $hashsumlength = $hlen{int $self->{HASHTYPE}} || $hlen{1};
	my $shorturlmaxlen = $self->{SHORTURLMAXLEN} || 16 ;
	my $storagemaxlen = 64;
	$self->{db_structure} = {

        'uploads' => 'mpath varchar(64), 
					  urlpath varchar(' . $shorturlmaxlen . ') ' . ($t eq'mysql'?'binary':'') . ',
					  storage varchar(' . $storagemaxlen . '),
					  rpath varchar('. $self->{FNMAXLEN} .'),
					  type varchar(8), hashsum varchar(' . $hashsumlength . '), 
					  ftype varchar(32),
					  link varchar(' . ($self->{FNMAXLEN} + $storagemaxlen + $shorturlmaxlen) . '), shorturl bool,
                      created int unsigned, expires int unsigned, autodestroy bool, autodestroylocked bool, wasdup bool, 
                      proto varchar(8), size bigint unsigned, hits bigint unsigned, processing smallint unsigned, scanned bool, oniononly bool, oniononlylocked bool,
                      primary key (mpath, urlpath)' . ($t eq'mysql'?', index(rpath), index(hashsum), index(expires), index(link)':''),
                      
        'reports' => 'time int unsigned, 
					  url varchar(' . $shorturlmaxlen . '),
					  email varchar(254),
					  comment text',
					  
        'captcha' => 'cid varchar(16) primary key, 
					  expiretime int unsigned,
					  text varchar(10)' . ($t eq'mysql'?', index(expiretime)':'')
					  

	};
	
}

sub check_captcha {
	my ($self, $text, $token) = @_;

	if ( $text && $token )
	{
		my $ctext = $self->captcha_token('get', $token);
		if ( $ctext ) {
			$self->captcha_token('delete', $token);
			return 1 if $ctext eq $text;
		} else {
			return -1;
		}
	}
	
	return 0;
}

sub captcha_token {
	my ($self, $op, $data) = @_;
	
	if ( $op eq 'get' ) {
		my $row = $self->db_get_row('captcha', 'cid', $data);
		return ($row ? $row->{'text'} : 0);
	}elsif ( $op eq 'delete' ) {
		$self->{dbc}->run(sub {
			$_->do("delete from captcha where cid = ?", undef, $data );
		});
	}elsif ( $op eq 'add' ) {
		$self->{dbc}->run(sub {
			$_->do("replace into captcha values (?,?,?)", undef, $data->[0], (time + int $self->{CAPTCHA_TOKEN_TIME}), $data->[1] );
		});

	}
}

sub captcha_purge_expired {
	my ($self) = @_;
	
	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select cid from captcha where time < ?');
	    $sth->execute(time);
	    $sth;
	});
	
	while (my $data = $sth->fetchrow_array) {
		$self->captcha_token('delete', $data);
	}
}


sub files_purge_expired {
	my ($self, $limit) = @_;
	
	my $limitsql = '';
	$limitsql = "limit $limit" if $limit;
	
	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select mpath from uploads where expires > 0 and expires < ? ' . $limitsql);
	    $sth->execute(time);
	    $sth;
	});
	
	while (my $data = $sth->fetchrow_array) {
		$self->delete_file('mpath', $data, 'fg');
		say "[info] $data - file deleted" if $self->{conf}->{DEBUG} > 0;
	}
}


sub files_purge_inexistent {
	# find and wipe database records of files not present on the disk
	my ($self, $findonly) = @_;
	my $inexistent = [];
	my $linkscount = 0;

	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select mpath, urlpath, storage, rpath from uploads where created < ? and type = "file"');
	    $sth->execute( (time - 3600) );
	    $sth;
	});
	
	while (my $row = $sth->fetchrow_hashref) {
		my $file = $self->build_filepath( $row->{'storage'},$row->{'urlpath'},$row->{'rpath'} );

		if ( ! -f $file ) {
			say "[info] $file - file not found on disk" if $self->{conf}->{DEBUG} > 0;
			
			push @{$inexistent}, $row;
			
			$self->{dbc}->run(sub {	$linkscount += int $_->selectrow_array("select count(*) from uploads where type = ? and link = ?", undef, 'link', $file) });

			unless  ($findonly) {
				$self->{dbc}->run(sub {	$_->do("delete from uploads where mpath = ? or link = ?", undef, $row->{'mpath'}, $file ) });
			}
		}
	}
	
	say "[info] found " . ( $findonly ? '' : 'and wiped ' ) . (scalar @{$inexistent}) . " file records and $linkscount link records" if $self->{conf}->{DEBUG} > 0;
	
	return $inexistent;
}


sub files_purge_untracked {
	# purge files not present in the database
	# those can remain due to hardware/power failures and similar situations when the file isn't properly deleted
	my ($self) = @_;
	
	chdir $self->{conf}->{UPLOAD_STORAGE_PATH} or die "cannot chdir: $!\n";
	
	my $dirname = './';
	opendir my $dh , $dirname or die "Couldn't open dir '$dirname': $!";
	my @files = readdir $dh;
	closedir $dh;
	
	my $db_found = 0;
	my $db_notfound = 0;
	
	foreach my $filename (@files) 
	{
	
		next if $filename =~ /^\.\.?$/;
		if ( $filename =~ /^([a-zA-Z]+)\_/ ) {
			my $urlpath = $1;
			my $row =  $self->{'dbc'}->dbh->selectrow_hashref("SELECT * FROM uploads WHERE urlpath = ? or link like ?", undef, $urlpath, $self->{conf}->{UPLOAD_STORAGE_PATH} . $urlpath . '_%');
			if ($row) {
				$db_found++;
			} else {
				try {
					unlink $filename;
					# really need some logging event here...
				} catch {
					say '[deletion failure] $_';
				};
				$db_notfound++;
			}
		} else {
			say 'Weird filename: ' . $filename if $self->{conf}->{DEBUG} > 0;
		}
	
	}
	
	#say "Found in the database: $db_found" if $self->{conf}->{DEBUG} > 0;
	say "Not found in the database and removed: $db_notfound" if $self->{conf}->{DEBUG} > 0;
}


sub files_antivirus_scan {
	my ($self) = @_;

	my $sqltypelist = '';
	$sqltypelist = ' and ( ' . join(' or ', map { 'ftype = "' . $_ . '"' } @{$self->{CLAMAV_FILE_TYPES}}) . ' )' if @{$self->{CLAMAV_FILE_TYPES}};
	
	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select * from uploads where type = "file" and scanned = 0' . $sqltypelist);
	    $sth->execute();
	    $sth;
	});
	
	while (my $row = $sth->fetchrow_hashref) {

		 try {
			my  $filename = $self->build_filepath($row->{'storage'}, $row->{'urlpath'}, $row->{'rpath'});
			say "[info] $filename - scanning file with clamav" if $self->{conf}->{DEBUG} > 0;
	
			my ($path,$r) =  $self->{clamav}->scan_path($filename);
			if ($r) {
				say "[info] $filename is infected: $r" if $self->{conf}->{DEBUG} > 0;
				$self->{dbc}->run(sub {
						$_->do("update uploads set autodestroy=1,autodestroylocked=1,scanned=1 where mpath = ?", undef, $row->{'mpath'} );
				});
				
				if ( defined $self->{conf}->{CLAMAV_SCANS_LOG} ) {
					open my $f, '>>', $self->{conf}->{CLAMAV_SCANS_LOG};
					print $f "[info] $filename ($row->{'hashsum'} $row->{'ftype'}) is infected: $r"; print $f "\n\n";
					close $f;
				}
			} else {
				say "[info] $filename is clean" if $self->{conf}->{DEBUG} > 0;
				$self->{dbc}->run(sub {
						$_->do("update uploads set scanned=1 where mpath = ?", undef, $row->{'mpath'} );
				});
			}
		 } catch {
			 say "[error] " . $_;
		 };

	}
}


sub db_parse_struct {
	my $self = shift;
	 
	$self->{db_tables} = {};
	 
	foreach my $t ( keys %{ $self->{db_structure} } ) {
		$self->{db_tables}->{$t} = [];
		$self->{db_structure}->{$t} =~ s/\n//g;
		my @columns = split ',', $self->{db_structure}->{$t};
		foreach(@columns)
		{
			s/^\s+//;
			s/\s+$//;
			if(/^([^\s]+)(.*)/)
			{
			 my $column = $1;
			 my $type = $2;
			 $type =~ s/^\s+//;
			 $type =~ s/\s+$//;
			 push @{$self->{db_tables}->{$t}}, [$column, $type];
			}
		}
	}
}


sub db_check_tables {
	my $self = shift;
	my $return = undef;
	my $dbh = $self->{'dbc'}->dbh;
	
	foreach my $table (keys %{$self->{db_tables}})
	{
		try {
			$dbh->do("select 1 from $table limit 1");
			#alter table uploads change urlpath urlpath varchar(16) binary;

			if ( $table eq 'uploads' and lc $self->{conf}->{DB_TYPE} eq 'mysql' ) {
				my $urlpath_needfix = $dbh->selectrow_array('select collation_name from information_schema.columns where table_name = ? and column_name = ?', undef, 'uploads', 'urlpath');
				unless ($urlpath_needfix =~ /_bin$/) {
					my $shorturlmaxlen = $self->{SHORTURLMAXLEN} || 16 ;
					$dbh->do("alter table uploads change urlpath urlpath varchar(" . $shorturlmaxlen . ") binary");
					my $urlpath_isfixed = $dbh->selectrow_array('select collation_name from information_schema.columns where table_name = ? and column_name = ?', undef, 'uploads', 'urlpath');
					say "[info] changed collation of `urlpath` column from $urlpath_needfix to $urlpath_isfixed";
				}
				my $oniononly_patch = $dbh->selectrow_array('select column_name from information_schema.columns where table_name = ? and column_name = ?', undef, 'uploads', 'oniononly');
				unless ($oniononly_patch) {
					$dbh->do("alter table uploads add column oniononly bool default 0 after scanned, add column oniononlylocked bool default 0 after oniononly");
					my $oniononly_patched = $dbh->selectrow_array('select column_name from information_schema.columns where table_name = ? and column_name = ?', undef, 'uploads', 'oniononly');
					say "[info] added `oniononly` and `oniononlylocked` columns" if $oniononly_patched;
				}
			}

		}
		catch 
		{
			if ( $_ =~ /(no such table)|(Table .+ doesn\'t exist)/)
			{
				say "No table $table, creating...\n";
			
				my $columns = join(',', map { $_->[0] . ' ' . $_->[1] } @{$self->{db_tables}->{$table}});
				my $REQ = "create table $table($columns)";
				say $REQ;
				$dbh->do($REQ); 
				if ( $DBI::errstr )
				{ 
					say "FATAL: creating table $table:";
					die($DBI::errstr);
				}
				$return = 1;
				say "Table created: $table";
			}
		};
	}
	return $return;
}

sub admin_auth {
	my ($self, $authstring) = @_;

	my ($user, $pass) = split ':', $authstring;
	return unless defined $user or defined $pass;
	return if $user ne $self->{conf}->{ADMIN_BASICAUTH_USER};
	return if sha256_hex($pass) ne $self->{conf}->{ADMIN_BASICAUTH_PASSWORDHASH};
	return 1;
}

1;
