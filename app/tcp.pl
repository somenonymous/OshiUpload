#!/usr/bin/perl
# tcp upload server

use strict;
use warnings;
use feature 'say';
use bytes;

use Mojo::IOLoop;
use AnyEvent::Socket;

use MIME::Base64;

require "./functions.pm";
my $main = OshiUpload->new->db_init;

my $domain = $main->{conf}->{UPLOAD_DOMAIN_CLEARNET};
my $storage_path = $main->{conf}->{UPLOAD_STORAGE_PATH};
my $admin_route = $main->{conf}->{UPLOAD_MANAGE_ROUTE};

my $PORTS = {
	'RAW' => { port => $main->{conf}->{TCP_RAW_PORT} || 7777, address => $main->{conf}->{TCP_RAW_ADDRESS} },
	'BASE64' => { port => $main->{conf}->{TCP_BASE64_PORT} || 7778, address => $main->{conf}->{TCP_BASE64_ADDRESS} },
	'HEX' => { port => $main->{conf}->{TCP_HEX_PORT} || 7779, address => $main->{conf}->{TCP_HEX_ADDRESS} }
};
# no data after connection for n secs
my $INACTIVE_TIMEOUT_CONNECTION = $main->{conf}->{TCP_INACTIVE_TIMEOUT_CONNECTION} || 4;
# no data for n secs after upload start and before eof
my $INACTIVE_TIMEOUT_UPLOAD = $main->{conf}->{TCP_INACTIVE_TIMEOUT_UPLOAD} || 30;
# in MB, the maximum upload size
my $FILE_MAX_SIZE = $main->{conf}->{TCP_UPLOAD_FILE_MAX_SIZE} || 150;
# in MB, the maximum RAM allowed for buffers (refuse new connections when over limit)
my $MEM_MAX_SIZE = $main->{conf}->{TCP_UPLOAD_MEMORY_MAX_SIZE} || 2000; 

my $DEBUG = $main->{conf}->{TCP_DEBUG} || 1;

my $file_max_size_bytes = $FILE_MAX_SIZE * 1048576;
my $buffers_max_size_bytes = $MEM_MAX_SIZE * 1048576;
my %ctimers; # dataless connections timers
my %iorefs; # active upload connections $io references to %uploads
my %uploads; # active upload connections data

 Mojo::IOLoop->recurring(1 => sub {
	foreach(keys %uploads ) {
		my $name = $_;
		if ( $uploads{$name}->{finished} ) {
			
			return if $uploads{$name}->{oncopy};
			
			say "$name is finished, starting copy" if $DEBUG;
			say "Length: " . $uploads{$name}->{length} if $DEBUG;
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
			    my ($subprocess, $err, @results) = @_;
			    say "$name copied to " . $file if $DEBUG;
					$main->process_file(	
										'tcp',
										$uploads{$name}->{mpath},
										$storage_path,
										$name, 
										$name, 
										$uploads{$name}->{length},
										1,
										$uploads{$name}->{expire}
									);
									
					
						
						
						
				delete $uploads{$name};
			  }
			);
			
			$uploads{$name}->{oncopy} = 1;
		}
		
	}
 });

tcp_server $PORTS->{'RAW'}->{address}||undef, $PORTS->{'RAW'}->{port}, sub {
	my ($fh, $host, $port)  = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $fh, 'RAW');
};

tcp_server $PORTS->{'BASE64'}->{address}||undef, $PORTS->{'BASE64'}->{port}, sub {
	my ($fh, $host, $port)  = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $fh, 'BASE64');
};

tcp_server $PORTS->{'HEX'}->{address}||undef, $PORTS->{'HEX'}->{port}, sub {
	my ($fh, $host, $port)  = @_;

	my $io;
	my $proginactivity;
	my $inactivity;

	tcp_server_process($io, $proginactivity, $inactivity, $fh, 'HEX');
};

sub tcp_server_process {
	my $io = shift;
	my $proginactivity = shift;
	my $inactivity = shift;
	my $fh = shift;
	my $type = shift;
	
	printf ("Client connected (%s)\n", $fh) if $DEBUG;

	my $onbuffers = 0;
	$onbuffers += $uploads{$_}->{length} foreach keys %uploads;
	if ( $onbuffers >= $buffers_max_size_bytes ) {
		syswrite $fh, "Can't accept your upload due to high load, please try again in a few minutes\n";
		return;
	}
	
	$iorefs{$fh} = { name => $main->newfilename(), nameadmin => $main->newfilename('manage') };
	
	my $name = $iorefs{$fh}->{name};
    my $nameadmin = $iorefs{$fh}->{nameadmin};
    my $resp = make_response($name, $nameadmin);
	syswrite $fh, "$resp\nStarting file transfer" . ($type ne 'RAW' ? " in $type mode" : '') . "\n";

	$inactivity = Mojo::IOLoop->timer($INACTIVE_TIMEOUT_CONNECTION => sub {
		my $loop = shift;
		syswrite $fh, "You're inactive, closing connection\n";
		
		$loop->remove($proginactivity);
		delete $ctimers{$inactivity};
		delete $uploads{$iorefs{$fh}->{name}} if exists $uploads{$iorefs{$fh}->{name}};
		delete $iorefs{$fh};
		undef $io;
	});
	$ctimers{$inactivity} = '';

	$io = AnyEvent->io (fh => $fh, poll => 'r', cb => sub {
		
		
		my $input = read ($fh, my $data, 8192);
		
		if (!$input) {
			
			say "$fh closed" if $DEBUG;
			$uploads{$iorefs{$fh}->{name}}->{finished} = 1 if (exists $iorefs{$fh} and exists $uploads{$iorefs{$fh}->{name}}) ;
			undef $io;
			Mojo::IOLoop->remove($inactivity);
			delete $ctimers{$inactivity};
			Mojo::IOLoop->remove($proginactivity);
			delete $iorefs{$fh};
			
		} else {
			
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
				syswrite $fh, "Your file exceeded ${FILE_MAX_SIZE}MB, aborting upload\n";
				undef $io;
				Mojo::IOLoop->remove($inactivity);
				Mojo::IOLoop->remove($proginactivity);
				delete $ctimers{$inactivity};
				delete $uploads{$iorefs{$fh}->{name}};
				delete $iorefs{$fh};
			}
			
		}
		
	});
	$proginactivity = Mojo::IOLoop->recurring(1 => sub {
			my $loop = shift;
			return unless exists $iorefs{$fh};
			if ( $iorefs{$fh}->{lastchunk} && (time - $iorefs{$fh}->{lastchunk}) > $INACTIVE_TIMEOUT_UPLOAD ) {
				say "$io is inactive" if $DEBUG;
				$uploads{$iorefs{$fh}->{name}}->{finished} = 1;
				undef $io;
				$loop->remove($proginactivity);
			}
	});
	
}

sub make_response {
	my $path = shift;
	my $mpath = shift;

	return $main->textonly_output($path,$mpath);
}


Mojo::IOLoop->start;
