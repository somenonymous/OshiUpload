package OshiUpload;

use feature 'say';
use strict;
use warnings;
use File::LibMagic;
use Digest::SHA qw/sha1_hex sha256_hex/;
use Data::Random qw(:all);
use Short::URL;
use URI::Encode qw(uri_encode uri_decode);
use Time::HiRes;
use DBIx::Connector;
use Try::Tiny;
use Scalar::Util qw/looks_like_number/;

sub new {
 my($class, %o) = @_;
 
 my $self = bless({}, $class);
 
 my $configpath = exists $o{configpath} ? $o{configpath} : "config";

 $self->load_config($configpath);
 $self->checkups;

 $self->{ShortURL} = Short::URL->new;
 $self->{ShortURL}->alphabet([qw/a b c d e f g h i j k m n o p q r s t u v w x y z A B C D E F G H J K L M N P Q R S T U V W X Y Z/]);

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
		ABUSE_CAPTCHA_REQUIRED => $self->{conf}->{CAPTCHA_SHOW_FOR_ABUSE},
	};

	return $g;
}

sub textonly_output {
	my ($self, $path, $mpath) = @_;

	my $str = $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN} . '_PROTO'} . '://' .  
			  $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}}  . 
			  $self->{conf}->{UPLOAD_MANAGE_ROUTE} . $mpath . " [Admin]\r\n";

	$str .= $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN} . '_PROTO'} . '://' . 
			$self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}} . '/' . $path . " [CDN download]\r\n";
			
	$str .= $self->{conf}->{'UPLOAD_DOMAIN_CLEARNET_PROTO'} . '://' . 
			$self->{conf}->{'UPLOAD_DOMAIN_CLEARNET'} . '/' . $path . " [Direct IP download]\r\n";
			
	$str .= $self->{conf}->{'UPLOAD_DOMAIN_ONION_PROTO'} . '://' . 
			$self->{conf}->{'UPLOAD_DOMAIN_ONION'} . '/' . $path . " [Tor download]\r\n";
			
	return $str;

}

sub checkups {
	my $self = shift;
	
	die "UPLOAD_FILENAME_MAX_LENGTH is not defined" unless exists $self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH};
	die "UPLOAD_DOMAIN_MAIN is not defined" unless exists $self->{conf}->{UPLOAD_DOMAIN_MAIN};
	die $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}} . " is not defined" unless exists $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_MAIN}};

	if ( exists $self->{conf}->{UPLOAD_DOMAIN_SHOW_SECONDARY_UPLOAD_LINK}
	     && $self->{conf}->{UPLOAD_DOMAIN_SHOW_SECONDARY_UPLOAD_LINK} == 1 ) {
	 die "UPLOAD_DOMAIN_SECONDARY is not defined" unless exists $self->{conf}->{UPLOAD_DOMAIN_SECONDARY};
	 die $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_SECONDARY}} . " is not defined" unless exists $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_SECONDARY}};
	}
	if ( exists $self->{conf}->{UPLOAD_DOMAIN_SHOW_TERTIARY_UPLOAD_LINK}
	     && $self->{conf}->{UPLOAD_DOMAIN_SHOW_TERTIARY_UPLOAD_LINK} == 1 ) {
	 die "UPLOAD_DOMAIN_TERTIARY is not defined" unless exists $self->{conf}->{UPLOAD_DOMAIN_TERTIARY};
	 die $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_TERTIARY}} . " is not defined" unless exists $self->{conf}->{$self->{conf}->{UPLOAD_DOMAIN_TERTIARY}};
	}

	unless ( exists $self->{conf}->{CONTENT_VIEW_BEFORE_SIZE} && looks_like_number $self->{conf}->{CONTENT_VIEW_BEFORE_SIZE} ) {
		$self->{conf}->{CONTENT_VIEW_BEFORE_SIZE} = 2000000;
	}
	
	$self->{SHORTURLMAXLEN} = 16;
	$self->{FNMAXLEN} = exists $self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH}?$self->{conf}->{UPLOAD_FILENAME_MAX_LENGTH}:100;
	$self->{FNMAXLEN} -= $self->{SHORTURLMAXLEN}; 
	$self->{HASHTYPE} = exists $self->{conf}->{UPLOAD_TRACK_DUPLICATES_HASHTYPE}?$self->{conf}->{UPLOAD_TRACK_DUPLICATES_HASHTYPE}:1;
	$self->{CAPTCHA_TOKEN_TIME} = exists $self->{conf}->{CAPTCHA_TOKEN_EXPIRE_TIME} ? $self->{conf}->{CAPTCHA_TOKEN_EXPIRE_TIME} : 300;
	$self->{CAPTCHA_TOKEN_TIME} = 300 if int $self->{CAPTCHA_TOKEN_TIME} < 1;
	
}

sub newfilename {
	my $self = shift;
	my $type = shift || '';
	my $filename = shift || '';
	
	my $randomstr = rand_chars ( set => 'alpha', min => 10, max => 20 );
	
	if ( $type eq 'manage' ) {
		return sha1_hex(Time::HiRes::time . $randomstr);
	}
	elsif ( $type eq 'random' ) {
		my $ext = '';
		$ext = $1 if $filename =~ /(\.[^\s\.]+)$/;
		return rand_chars ( set => 'alpha', min => 4, max => 4 ) . $ext;
	}
	
	my $randomname = $self->{ShortURL}->encode( (10+int(rand(99))) . substr(CORE::time, 2) );
	my $try = 0;
	while ( $try < 5) {
		$try++;
		if ( $self->db_get_row('uploads', 'urlpath', $randomname) ) {
			say '[info] Duplicate generated, adding random char' . "($randomname)" if $self->{conf}->{DEBUG} > 0;
			$randomname .= rand_chars ( set => 'alpha', min => 1, max => 1 );
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
	
	my $file = $self->build_filepath($storage,$url,$filename);
	
	if ( defined $expire && $expire == 0 ) {
		$expire = 0;
	}elsif ( !$expire ) {
		$expire = $self->{conf}->{UPLOAD_TIME_DEFAULT}
	}
	
	Mojo::IOLoop->subprocess(
	  sub {
	    my $subprocess = shift;
	    
		my $isdup = 0;
		my $type = 'file';
		my $linktarget;
		my $link = '';
		  
		if ( $self->db_get_row('uploads', 'urlpath', $url) ) {
			say '[fatal] URL already exists in DB ' . "($url)" if $self->{conf}->{DEBUG} > 0;
			### newfilename() checks whether generated short url already exists, but 
			### race-conditions may happen anyway between two+ hypnotoad workers under relatively high load.
			### for now i decided to not process anyhow these cases, this may change in future
			return 0;
			###
			my $oldfile = $file;
			$url = substr($mpath,0,5) . $url;
			$isdup = 1;
			$file = $self->build_filepath($storage,$url,$filename);
			if ( -f $file ) {
				# this is a fatal condition
				die('Found a duplicate after a found duplicate in DB: ' . $file);
			}
			rename ($oldfile, $file) or die($!);
		}


		my $fh;
		unless (open $fh, $file) {
			die "process_file: open $file: $!";
		}
		
		$self->{dbc}->run(sub {
			my $dbh = shift;
			$dbh->do("insert into uploads (mpath, urlpath, processing) values (?,?,1)", undef, $mpath, $url);
		});

		my $sha = Digest::SHA->new($self->{HASHTYPE});
		$sha->addfile($fh);
		my $hash = $sha->hexdigest;
		close $fh;
		
		my $ftype;
		try { $ftype = $self->{libmagic}->info_from_filename($file)->{mime_type} };
		$ftype = 'unknown/unknown' if length($ftype) < 2;
		$ftype = substr($ftype,0,32);
		
		if ( exists $self->{conf}->{UPLOAD_TRACK_DUPLICATES} && $self->{conf}->{UPLOAD_TRACK_DUPLICATES} == 1 )
		{
			my $hashexists;
			$self->{dbc}->run(sub {
				$hashexists = $_->selectrow_hashref("SELECT * FROM uploads WHERE hashsum = ? and type = 'file' and ( expires = 0 or expires > ? ) LIMIT 1", undef, $hash, (time + 300));
			});
			if ( $hashexists ) {
				say '[info] Duplicate file exists with the same hash' if $self->{conf}->{DEBUG} > 0;

				# only make link if expire time is more than 5 minutes from now or file never expire (0)
				if ( ($hashexists->{expires} - time) > 300 || $hashexists->{expires} == 0 ) {
					if ( $ftype eq $hashexists->{ftype} and $size == $hashexists->{size} ) {
						say '[info] Creating link' if $self->{conf}->{DEBUG} > 0;
						
						$link = $self->build_filepath($hashexists->{storage},$hashexists->{urlpath},$hashexists->{rpath});
						if ( -f $link  ) {
							$type = 'link';
							unlink $file;
						} else {
							say '[warn] Tried to create a link, but target file does not exist' if $self->{conf}->{DEBUG} > 0;
							$link = '';
						}
					}
				}
			}
		}
		
		# try { utf8::decode($filename) };
		
		my @values = (	$mpath, $url, $storage, $filename, $type, $hash, $ftype, $link, $shorturl,
						time, ( $expire == 0 ? 0 : (time+($expire*60)) ), $destroyafterload, 0, $isdup, $proto, $size, 0, 0	);
		
		$self->{dbc}->run(sub {
			my $dbh = shift;
			$dbh->do("replace into uploads values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)", undef, @values);
		});

		return 1;
		
	  },
	  sub {
	    my ($subprocess, $err, $h) = @_;
	    do { # fatal
			say '[fatal] ' . $err; 
			return 
			} if $err;
	    say '[info] Upload complete'  if $self->{conf}->{DEBUG} > 0;
	  }
	);
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

	if ( $runmode ) {
		$self->delete_file_job( $select_by, $id );
	} else {
		Mojo::IOLoop->subprocess(
			sub {
				my $subprocess = shift;
				$self->delete_file_job( $select_by, $id );
				return 1;
			},
			sub {
				my ($subprocess, $err, $row) = @_;
	
			}
		);
	}

	
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
					  urlpath varchar(' . $shorturlmaxlen . '),
					  storage varchar(' . $storagemaxlen . '),
					  rpath varchar('. $self->{FNMAXLEN} .'),
					  type varchar(8), hashsum varchar(' . $hashsumlength . '), 
					  ftype varchar(32),
					  link varchar(' . ($self->{FNMAXLEN} + $storagemaxlen + $shorturlmaxlen) . '), shorturl bool,
                      created int unsigned, expires int unsigned, autodestroy bool, autodestroylocked bool, wasdup bool, 
                      proto varchar(8), size bigint unsigned, hits bigint unsigned, processing smallint unsigned, scanned bool,
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
	my ($self) = @_;
	
	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select mpath from uploads where expires > 0 and expires < ?');
	    $sth->execute(time);
	    $sth;
	});
	
	while (my $data = $sth->fetchrow_array) {
		say "[info] $data - file deleted" if $self->{conf}->{DEBUG} > 0;
		$self->delete_file('mpath', $data, 'fg');
	}
}


sub files_antivirus_scan {
	my ($self) = @_;
	
	my $sth = $self->{dbc}->run(sub {
	    my $sth = $_->prepare('select mpath,storage,urlpath,rpath from uploads where type = "file" and scanned = 0 and (ftype = "application/x-dosexec" or ftype = "application/x-executable")');
	    $sth->execute();
	    $sth;
	});
	
	while (my $row = $sth->fetchrow_hashref) { # 
		if ( $self->{conf}->{CLAMAV_SCANS_ENABLED} ) {
		 try {
			my  $filename = $self->build_filepath($row->{'storage'}, $row->{'urlpath'}, $row->{'rpath'});
			say "[info] $filename - scanning file with clamav" if $self->{conf}->{DEBUG} > 0;
	
			my ($path,$r) =  $self->{clamav}->scan_path($filename);
			if ($r) {
				say "[info] $filename is infected: $r" if $self->{conf}->{DEBUG} > 0;
				$self->{dbc}->run(sub {
						$_->do("update uploads set autodestroy=1,autodestroylocked=1,scanned=1 where mpath = ?", undef, $row->{'mpath'} );
				});
				open my $f, '>>', '/tmp/infected_uploads_log';
				print $f "[info] $filename is infected: $r"; print $f "\n\n";
				close $f;
			} else {
				say "[info] $filename is clean" if $self->{conf}->{DEBUG} > 0;
				$self->{dbc}->run(sub {
						$_->do("update uploads set scanned=1 where mpath = ?", undef, $row->{'mpath'} );
				});
			}
		 };
		}
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
			$dbh->do("select 1 from $table limit 1") 
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
