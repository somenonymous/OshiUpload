#!/usr/bin/perl
# tcp upload server

use strict;
use warnings;
use feature 'say';
use bytes;

use Mojo::IOLoop;

use MIME::Base64;

require "./functions.pm";
my $main = OshiUpload->new->db_init;

my $domain = $main->{conf}->{UPLOAD_DOMAIN_CLEARNET};
my $storage_path = $main->{conf}->{UPLOAD_STORAGE_PATH};
my $admin_route = $main->{conf}->{UPLOAD_MANAGE_ROUTE};

my $PORTS = {
	'RAW' => { port => $main->{conf}->{TCP_RAW_PORT}, address => $main->{conf}->{TCP_RAW_ADDRESS} },
	'BASE64' => { port => $main->{conf}->{TCP_BASE64_PORT}, address => $main->{conf}->{TCP_BASE64_ADDRESS} },
	'HEX' => { port => $main->{conf}->{TCP_HEX_PORT}, address => $main->{conf}->{TCP_HEX_ADDRESS} }
};
# no data after connection for n secs
my $INACTIVE_TIMEOUT_CONNECTION = $main->{conf}->{TCP_INACTIVE_TIMEOUT_CONNECTION} || 4;
# no data for n secs after upload start and before eof
my $INACTIVE_TIMEOUT_UPLOAD = $main->{conf}->{TCP_INACTIVE_TIMEOUT_UPLOAD} || 30;
# in MB, the maximum upload size
my $FILE_MAX_SIZE = $main->{conf}->{TCP_UPLOAD_FILE_MAX_SIZE} || 150;
# in MB, the maximum RAM allowed for buffers (refuse new connections when over limit)
my $MEM_MAX_SIZE = $main->{conf}->{TCP_UPLOAD_MEMORY_MAX_SIZE} || 1000; 

my $DEBUG = defined $main->{conf}->{TCP_DEBUG} ? int $main->{conf}->{TCP_DEBUG} : 1;
my $debugpre = '[tcp]';

my $file_max_size_bytes = $FILE_MAX_SIZE * 1048576;
my $buffers_max_size_bytes = $MEM_MAX_SIZE * 1048576;
my %ctimers; # dataless connections timers
my %iorefs; # active upload connections $io references to %uploads
my %uploads; # active upload connections data

my @hashqueue;
my %hashqueue_running;
my $hashqueue_maxjobs = 4;
if ( $main->{conf}->{UPLOAD_HASH_CALCULATION} ) {
	Mojo::IOLoop->recurring(0.1 => sub {
		my $ioloop = shift;
		if ( @hashqueue && keys(%hashqueue_running) < $hashqueue_maxjobs) {
			my $fileid =  shift @hashqueue;
			$hashqueue_running{$fileid} = '';
			my $subprocess = $ioloop->subprocess(sub {
				say $debugpre . "[info] started process_file_hashsum for " . $fileid if $DEBUG or $main->{conf}->{DEBUG} > 0;
				$main->process_file_hashsum( $fileid );
			}, sub {
				my ($subprocess, $err, @results) = @_;
				say $debugpre . "[error] $fileid - " . $err if $err && ($DEBUG or $main->{conf}->{DEBUG} > 0);
				say $debugpre . "[info] finished process_file_hashsum for " . $fileid if $DEBUG or $main->{conf}->{DEBUG} > 0;
				delete $hashqueue_running{$fileid};
			});
		}
	});
}

Mojo::IOLoop->recurring(1 => sub {
	foreach(keys %uploads ) {
		my $name = $_;
		if ( $uploads{$name}->{finished} ) {
			
			return if $uploads{$name}->{oncopy};
			
			say $debugpre . " $name is finished, starting copy" if $DEBUG;
			say $debugpre . " $name Length: " . $uploads{$name}->{length} if $DEBUG;
			my $file =  $main->build_filepath($storage_path,$name,$name);
			Mojo::IOLoop->subprocess(
			  sub {
			    my $subprocess = shift;
			    open my $f, '>', $file or die($!);
			    binmode $f;
				print $f pack('H*',$uploads{$name}->{data}) if $uploads{$name}->{type} eq 'HEX';
				print $f decode_base64($uploads{$name}->{data}) if $uploads{$name}->{type} eq 'BASE64';
				print $f $uploads{$name}->{data} if $uploads{$name}->{type} eq 'RAW';
				close $f;
			    return 1;
			  },
			  sub {
			    my ($subprocess, $err) = @_;
			    say $debugpre . '[error] ' .  $err if ( $err && $DEBUG );
			    say $debugpre . " $name copied to " . $file if $DEBUG;
			    
			    my @datatobackend = (	'tcp',
										$uploads{$name}->{mpath},
										$storage_path,
										$name, 
										$name, 
										$uploads{$name}->{length},
										1,
										$uploads{$name}->{expire}
									);
									
				delete $uploads{$name};

			    Mojo::IOLoop->subprocess(
				 sub {
				    my $subprocess = shift;
					$main->process_file( @datatobackend );
				  },
				  sub {
				    my ($subprocess, $err) = @_;
				    say $debugpre . '[error] ' .  $err if ( $err && $DEBUG );
					push @hashqueue, $datatobackend[1] if $main->{conf}->{UPLOAD_HASH_CALCULATION};
				  }
				);

			  }
			);
			
			$uploads{$name}->{oncopy} = 1;
		}
		
	}
});

Mojo::IOLoop->server({port => $PORTS->{'RAW'}->{port}||7777, address => $PORTS->{'RAW'}->{address}||'127.0.0.1' } => sub {
  my ($loop, $stream) = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $stream, 'RAW');
});

Mojo::IOLoop->server({port => $PORTS->{'BASE64'}->{port}||7778, address => $PORTS->{'BASE64'}->{address}||'127.0.0.1' } => sub {
  my ($loop, $stream) = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $stream, 'BASE64');
});

Mojo::IOLoop->server({port => $PORTS->{'HEX'}->{port}||7779, address => $PORTS->{'HEX'}->{address}||'127.0.0.1' } => sub {
  my ($loop, $stream) = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $stream, 'HEX');
});

sub tcp_server_process {
	my $io = shift;
	my $proginactivity = shift;
	my $inactivity = shift;
	my $fh = shift;
	my $type = shift;
	
	printf ($debugpre . " Client connected (%s)\n", $fh) if $DEBUG;

	my $onbuffers = 0;
	$onbuffers += $uploads{$_}->{length} foreach keys %uploads;
	if ( $onbuffers >= $buffers_max_size_bytes ) {
		$fh->write("Can't accept your upload due to high load, please try again in a few minutes\n");
		return;
	}
	
	$iorefs{$fh} = { name => $main->newfilename(), nameadmin => $main->newfilename('manage') };
	
	my $name = $iorefs{$fh}->{name};
    my $nameadmin = $iorefs{$fh}->{nameadmin};
    my $resp = make_response($name, $nameadmin);
	$fh->write("$resp\nStarting file transfer" . ($type ne 'RAW' ? " in $type mode" : '') . "\n");

	$inactivity = Mojo::IOLoop->timer($INACTIVE_TIMEOUT_CONNECTION => sub {
		my $loop = shift;
		$fh->write("You're inactive, closing connection\n");
		
		$loop->remove($proginactivity);
		delete $ctimers{$inactivity};
		delete $uploads{$iorefs{$fh}->{name}} if exists $uploads{$iorefs{$fh}->{name}};
		delete $iorefs{$fh};
		$fh->close_gracefully; 
	});
	$ctimers{$inactivity} = '';
	
	$fh->on(close => sub {
	  my $fh = shift;
				
			
			say "$debugpre $fh closed" if $DEBUG > 1;
			$uploads{$iorefs{$fh}->{name}}->{finished} = 1 if (exists $iorefs{$fh} and exists $uploads{$iorefs{$fh}->{name}}) ;
			$fh->close_gracefully; 
			Mojo::IOLoop->remove($inactivity);
			delete $ctimers{$inactivity};
			Mojo::IOLoop->remove($proginactivity);
			delete $iorefs{$fh};
			
	});
	
  $fh->on(read => sub {
    my ($fh, $data) = @_;

			do {
				Mojo::IOLoop->remove($inactivity); 
				delete $ctimers{$inactivity}
			} if exists $ctimers{$inactivity};

			unless ( exists $uploads{$iorefs{$fh}->{name}} ) {
				$uploads{$iorefs{$fh}->{name}} = { mpath => $nameadmin, finished => 0, oncopy => 0, length => 0, type => $type, data => '' };
			}
			
			$iorefs{$fh}->{lastchunk} = time;
			$uploads{$iorefs{$fh}->{name}}->{data} .= $data;
			
			$uploads{$iorefs{$fh}->{name}}->{length} += bytes::length($data);
			
			if ( $uploads{$iorefs{$fh}->{name}}->{length} > $file_max_size_bytes ) {
				$fh->write("Your file exceeded ${FILE_MAX_SIZE}MB, aborting upload\n");
					$fh->close_gracefully; 
				Mojo::IOLoop->remove($inactivity);
				Mojo::IOLoop->remove($proginactivity);
				delete $ctimers{$inactivity};
				delete $uploads{$iorefs{$fh}->{name}};
				delete $iorefs{$fh};
			}
			
  });

	$proginactivity = Mojo::IOLoop->recurring(1 => sub {
			my $loop = shift;
			return unless exists $iorefs{$fh};
			if ( $iorefs{$fh}->{lastchunk} && (time - $iorefs{$fh}->{lastchunk}) > $INACTIVE_TIMEOUT_UPLOAD ) {
				say "$debugpre $fh is inactive" if $DEBUG > 1;
				$uploads{$iorefs{$fh}->{name}}->{finished} = 1;
					$fh->close_gracefully; 
				$loop->remove($proginactivity);
			}
	});
	
}

sub make_response {
	my $path = shift;
	my $mpath = shift;

	return $main->textonly_output($path,$mpath);
}

say $debugpre . "[info] TCP upload server started (tcp.pl)" if $DEBUG or $main->{conf}->{DEBUG} > 0;
foreach (sort { $PORTS->{$a}->{port} <=> $PORTS->{$b}->{port} } keys %{$PORTS}) { 
	say $debugpre . "[info] Listening on $PORTS->{$_}->{address}:$PORTS->{$_}->{port} ($_)" if $DEBUG or $main->{conf}->{DEBUG} > 0 
}

Mojo::IOLoop->start;
