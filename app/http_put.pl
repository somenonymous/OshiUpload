#!/usr/bin/perl

# This is a very dummy HTTP server that process PUT uploads only, the only reason
# why I wrote it is atm there were no out-of-the-box solutions for uploading files with PUT in Perl
# and it's always fun to write some TCP stuff.
# This situation may change soon and we will move on to a more convenient solution whether me or someone else
# decides to write a decent addon for Mojolicious

### UPDATE:      Mojolicious now supports PUT uploads and it's integrated in webapp.pl
###              This program still can be used as a stand-alone server for PUT requests

use strict;
use warnings;
use feature 'say';
use bytes;

use Mojo::IOLoop;

use MIME::Base64;
use Scalar::Util qw/looks_like_number/;

require "./functions.pm";
my $main = OshiUpload->new->db_init;

my $domain = $main->{conf}->{UPLOAD_DOMAIN_CLEARNET};
my $storage_path = $main->{conf}->{UPLOAD_STORAGE_PATH};
my $admin_route = $main->{conf}->{UPLOAD_MANAGE_ROUTE};

my $PORTS = {
	'PUT' => { port => $main->{conf}->{HTTP_PUT_PORT} || 4020, address => $main->{conf}->{HTTP_PUT_ADDRESS} || '127.0.0.1' },

};
# no data after connection for n secs
my $INACTIVE_TIMEOUT_CONNECTION = $main->{conf}->{HTTP_PUT_INACTIVE_TIMEOUT_CONNECTION} || 4;
# no data for n secs after upload start and before eof
my $INACTIVE_TIMEOUT_UPLOAD = $main->{conf}->{HTTP_PUT_INACTIVE_TIMEOUT_UPLOAD} || 30;
# in MB, the maximum upload size
my $FILE_MAX_SIZE = $main->{conf}->{HTTP_UPLOAD_FILE_MAX_SIZE} || 1000;

my $DEBUG = defined $main->{conf}->{HTTP_PUT_DEBUG} ? int $main->{conf}->{HTTP_PUT_DEBUG} : 1;

my $file_max_size_bytes = $FILE_MAX_SIZE * 1048576;
my %ctimers; # dataless connections timers
my %iorefs; # active upload connections $io references to %uploads
my %uploads; # active upload connections data
my %uploads_chunks; # active upload connections sequential chunks (copy-on-write RAM buffer)

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
				say 'started process_file_hashsum for ' . $fileid if $DEBUG or $main->{conf}->{DEBUG} > 0;
				$main->process_file_hashsum( $fileid );
			}, sub {
				my ($subprocess, $err, @results) = @_;
				say '[error] ' . $err if $err && ($DEBUG or $main->{conf}->{DEBUG} > 0);
				say 'finished process_file_hashsum for ' . $fileid if $DEBUG or $main->{conf}->{DEBUG} > 0;
				delete $hashqueue_running{$fileid};
			});
		}
	});
}

Mojo::IOLoop->recurring(0.5 => sub {

	foreach(keys %uploads ) {
		my $name = $_;

		next if $uploads{$name}->{oncopy};

		unless ( keys %{$uploads_chunks{$name}} > 0 ) {
			if ( $uploads{$name}->{finished} ) {
				unless ( $uploads{$name}->{error} || $uploads{$name}->{length} < 1) {
					# upload completed, pass the filename to the core method
					my @datatobackend = (   'http_put',
											$uploads{$name}->{mpath},
											$storage_path,
											$uploads{$name}->{path}, 
											$uploads{$name}->{filename}, 
											$uploads{$name}->{length},
											1,
											$uploads{$name}->{expire}, 
											(exists $uploads{$name}->{autodestroy} ? $uploads{$name}->{autodestroy} : 0)
										);
					Mojo::IOLoop->subprocess(
					  sub {
						say "Processing upload - " . $name if $DEBUG;
						$main->process_file(@datatobackend);
					  },
					  sub {
					    my ($subprocess, $err) = @_;
						say '[error] ' .  $err if ( $err && $DEBUG );
						push @hashqueue, $datatobackend[1] if $main->{conf}->{UPLOAD_HASH_CALCULATION};
					  }
					);
				}
				delete $uploads{$name};
				delete $uploads_chunks{$name};
				delete $iorefs{$name} if exists $iorefs{$name};
			}
			
			next;
		}
		
		my $file =  $main->build_filepath($storage_path,$uploads{$name}->{path},$uploads{$name}->{filename});

		$uploads{$name}->{oncopy} = 1;
			Mojo::IOLoop->subprocess(
			  sub {
			    my $subprocess = shift;
			    open my $f, '>>', $file or die($!);
			    binmode $f;
			    my @done;
				foreach (sort {$a <=> $b} keys %{$uploads_chunks{$name}}) {
					print $f $uploads_chunks{$name}->{$_};
					push @done, $_;
				}
				close $f;
			    return @done;
			  },
			  sub {
			    my ($subprocess, $err, @count) = @_;
				$uploads{$name}->{oncopy} = 0;
				say "wrote data to " . $file if $DEBUG;
				foreach(@count){
					delete $uploads_chunks{$name}->{$_};
				}
			  }
			);
	}

});


Mojo::IOLoop->server({port => $PORTS->{'PUT'}->{port}, address => $PORTS->{'PUT'}->{address}} => sub {
  my ($loop, $stream) = @_;

	my $fh = $stream;
	
	my $inactivity;

	my $name = $main->newfilename();
	$iorefs{$name} = { 
		name => $name , 
		nameadmin => $main->newfilename('manage'),
		length => 0,
		chunk_count => 0,
		is_body => 0,
		header => '',
		content_length => 0,
		chunked_length => 0,
		lastchunk => time,
		proginactivity => 0
	};
	
	printf ("Client connected (%s) (%s)\n", $fh, $name) if $DEBUG;
	
	
	$inactivity = Mojo::IOLoop->timer($INACTIVE_TIMEOUT_CONNECTION => sub {
		my $loop = shift;
		$stream->write(wrap_final_response("You're inactive, closing connection")); 
		$stream->close_gracefully; 
		clean_on_abort($name); 
	});
	
	$ctimers{$inactivity} = '';
	
	$stream->on(close => sub {
	  my $stream = shift;
				
		say "$stream ($name) closed" if $DEBUG;
		$stream->close_gracefully; 
		clean_on_abort($name);
		finalize_transaction($name) if $iorefs{$name}->{is_body};

	});
	
  $stream->on(read => sub {
    my ($stream, $data) = @_;

			return if exists $uploads{$name} && $uploads{$name}->{finished};
			$iorefs{$name}->{chunk_count}++;

			if ( $iorefs{$name}->{is_body} ) {
				say "Got data from $name:" if $DEBUG > 1;
				
				if ( $iorefs{$name}->{chunked_length} > 0 && $iorefs{$name}->{chunked_length} == $iorefs{$name}->{chunk_count} ) {
					my $error;
					($data, $error) = process_encoding_chunked($name, $data);
					if ( $error ) {
							$stream->write(wrap_final_response($error));
							#undef $io; 
							$stream->close_gracefully; 
							clean_on_abort($name); return;
					}
				}
				
				$iorefs{$name}->{length} += bytes::length($data);

				if ( $iorefs{$name}->{length} >= $iorefs{$name}->{content_length} ) {
					
					my $lastchunk = $data;
					if ( $iorefs{$name}->{length} > $iorefs{$name}->{content_length} ) {

						$lastchunk = substr( $data, 0, bytes::length($data) - ($iorefs{$name}->{length} - $iorefs{$name}->{content_length}));
						
					}
					
					# copy last body chunk
					chunk_copy_to_ram($name, $iorefs{$name}->{chunk_count}, $lastchunk);
					finalize_transaction($name);
					
					#undef $io;
					
					
					
					$stream->write( wrap_final_response( make_response($uploads{$name}->{path},$uploads{$name}->{mpath}) ) );
					
					$stream->close_gracefully; 
					
				} else {
					$iorefs{$name}->{lastchunk} = time;
					# copy body chunk
					chunk_copy_to_ram($name, $iorefs{$name}->{chunk_count}, $data);
				}
				
			} elsif ( $iorefs{$name}->{chunk_count} >= 3 ) {
				$stream->write( wrap_final_response("No HTTP header present, closing connection") );
				#undef $io; 
				$stream->close_gracefully; 
				clean_on_abort($name); return;
			} else {
				# first data chunk is processed here
				Mojo::IOLoop->remove($inactivity) if exists $ctimers{$inactivity}; 
				if ( $data =~ /^(.+?)\r?\n\r?\n(.*)/s ) {

					$iorefs{$name}->{is_body} = 1;
					$iorefs{$name}->{header} .= $1;
					my $firstdatachunk = $2;
					
					say 'Got HTTP Header:' if $DEBUG;
					say $iorefs{$name}->{header} if $DEBUG;

					say 'Got body in a first chunk: ' . $firstdatachunk if $firstdatachunk && $DEBUG;
					
					my @headers = split /\r?\n/, $iorefs{$name}->{header};
					my $firstline = shift @headers;
					my %h; do {  $h{lc $1} = $2 if /^([^:]+):\s*(.+)/ } foreach @headers;
					
					if (exists $h{'content-length'}) {
						unless ( looks_like_number $h{'content-length'} ) {
							$stream->write( wrap_final_response("Wrong length format, closing connection") );
							#undef $io; 
							$stream->close_gracefully; 
							clean_on_abort($name); return;
						}
						if ( int $h{'content-length'} > $file_max_size_bytes ) {
							$stream->write( wrap_final_response("Your upload exceeds ${FILE_MAX_SIZE}MB, closing connection") );
							#undef $io; 
							$stream->close_gracefully; 
							clean_on_abort($name); return;
							
						}
						$iorefs{$name}->{content_length} = $h{'content-length'};
					} elsif (exists $h{'transfer-encoding'} and lc $h{'transfer-encoding'} eq 'chunked') {
						$iorefs{$name}->{chunked_length} = $iorefs{$name}->{chunk_count} + 1;
					} else {
						$stream->write( wrap_final_response("Content-length is missing in your headers, closing connection") );
						#undef $io; 
						$stream->close_gracefully; 
						clean_on_abort($name); return;
					}

					$uploads{$name} = { finished => 0, mpath => $iorefs{$name}->{'nameadmin'} } unless exists $uploads{$name};
					$uploads_chunks{$name} = { } unless exists $uploads_chunks{$name};
					$iorefs{$name}->{lastchunk} = time;


					if ( $firstline =~ /^[^\s]+\s+\/([^\s]+)\s+HTTP/ ) {
						my $f = $1;
						my $fname;
						
						if ( $f =~ /^([^\/]+)\/(\-?\d+)/ ) {
							$fname = $main->parse_filename($1);
							$uploads{$name}->{expire} = $2;
							
							 if (defined $uploads{$name}->{expire}) {
								 if ( $uploads{$name}->{expire} eq '-1' ) { 
									 $uploads{$name}->{autodestroy} = 1;
									 $uploads{$name}->{expire} = undef;
								 } else {
									my @ex = $main->expiry_check($uploads{$name}->{expire});
							
									if ( $ex[0] != 1 ) {
										$stream->write( wrap_final_response($ex[1]) );
										#undef $io; 
										$stream->close_gracefully; 
										clean_on_abort($name); finalize_transaction($name, 1);  return;
									}
								}
							}
							
						} else {
							$fname = $main->parse_filename($f);
						}
						$uploads{$name}->{filename} = $fname;
						$uploads{$name}->{path} = $name;

					}

					if ( $firstdatachunk && $iorefs{$name}->{chunked_length} > 0 ) {
						my $error;
						($firstdatachunk, $error) = process_encoding_chunked($name, $firstdatachunk);
						if ( $error ) {
								$stream->write( wrap_final_response($error) );
								#undef $io; 
								$stream->close_gracefully; 
								clean_on_abort($name); finalize_transaction($name, 1); return;
						}
					}
					
					$iorefs{$name}->{length} += bytes::length($firstdatachunk);
					
					if ( $iorefs{$name}->{length} >= $iorefs{$name}->{content_length} && !$iorefs{$name}->{chunked_length} ) {
						my $lastchunk = substr( $firstdatachunk, 0, $iorefs{$name}->{length} - ($iorefs{$name}->{content_length} - $iorefs{$name}->{length}) );
						
						# receive body last chunk
						chunk_copy_to_ram($name, $iorefs{$name}->{chunk_count}, $lastchunk);
						finalize_transaction($name);
						$stream->write( wrap_final_response( make_response($uploads{$name}->{path},$uploads{$name}->{mpath}) )  );
						#undef $io;
						$stream->close_gracefully; 
						return;
					} else {
						chunk_copy_to_ram($name, $iorefs{$name}->{chunk_count}, $firstdatachunk);
					}
				} else {
					$iorefs{$name}->{header} .= $data
				}
			}

  });
  

	$iorefs{$name}->{proginactivity} = Mojo::IOLoop->recurring(1 => sub {
			my $loop = shift;
			return unless exists $iorefs{$name};
			if ( $iorefs{$name}->{lastchunk} && (time - $iorefs{$name}->{lastchunk}) > $INACTIVE_TIMEOUT_UPLOAD ) {
				say "$stream is inactive" if $DEBUG;
				finalize_transaction($name);
				$stream->close_gracefully; 
			}
	});
	
});

say "[info] Standalone HTTP PUT server started (http_put.pl)" if $DEBUG or $main->{conf}->{DEBUG} > 0;
say "[info] Listening on $PORTS->{PUT}->{address}:$PORTS->{PUT}->{port} (PUT)" if $DEBUG or $main->{conf}->{DEBUG} > 0;

Mojo::IOLoop->start unless Mojo::IOLoop->is_running;



sub process_encoding_chunked {
	my $name = shift;
	my $data = shift;
	my @tdata = split /\r?\n/, $data;
	$data =~ s/^[^\r\n]+\r?\n//s;
	$iorefs{$name}->{content_length} = hex $tdata[0];
	unless ( looks_like_number $iorefs{$name}->{content_length} ) {
		return (0, "Wrong length format, closing connection");
	}
	if ( $iorefs{$name}->{content_length} > $file_max_size_bytes ) {
		return (0, "Your upload exceeds ${FILE_MAX_SIZE}MB, closing connection");
	}
	return ($data, undef);
}

sub clean_on_abort {
	my $name = shift;
	do {
		Mojo::IOLoop->remove($iorefs{$name}->{proginactivity});
		$iorefs{$name}->{proginactivity} = 0;
	} if $iorefs{$name}->{proginactivity};
	delete $iorefs{$name};
}

sub chunk_copy_to_ram {
		my $name = shift;
		my $seq = shift;
		my $data = shift;

		$uploads_chunks{$name}->{$seq} = $data;
}

sub wrap_final_response {
	my $response = shift;
	my $finish_http_header = "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n";
	return $finish_http_header . $response . "\r\n";
}

sub finalize_transaction {
	my ($name, $error) = @_;
	
	do {
		Mojo::IOLoop->remove($iorefs{$name}->{proginactivity});
		$iorefs{$name}->{proginactivity} = 0;
	} if $iorefs{$name}->{proginactivity};
	$uploads{$name}->{length} = $iorefs{$name}->{length} if exists $uploads{$name};
	$uploads{$name}->{finished} = 1 if exists $uploads{$name};
	$uploads{$name}->{error} = 1 if $error;
}

sub make_response {
	my $path = shift;
	my $mpath = shift;
	
	return "\r\n" . $main->textonly_output($path,$mpath);
}
