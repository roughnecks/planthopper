#!/usr/bin/perl
# -*- mode: cperl -*-

# No copyright

# This code is free software; you may redistribute it
# and/or modify it under the same terms as Perl itself.

# Tumblr IRC Perl Bot is based on BirbaBot
# Author: Simone 'roughnecks' Canaletti

use strict;
use warnings;

use utf8;
use Cwd;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common;
use HTML::Entities;
use Data::Dumper;
use lib './BirbaBot/lib';
use BirbaBot qw(read_config
		override_defaults
		show_help warn_and_quit);

use POE;
use POE::Component::Client::DNS;
use POE::Component::IRC::Common qw(parse_user l_irc irc_to_utf8);
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::BotCommand;
use POE::Component::IRC::Plugin::CTCP;
use YAML::Any qw/LoadFile/;

use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use JSON;

our $VERSION = '0.1';

my $lastpinged;
my $reconnect_delay = 150;
my $starttime = time;
my $bbold = "\x{0002}";
my $ebold = "\x{000F}";

$| = 1; # turn buffering off

# before starting, create a pid file
open (my $fh, ">", "tumblr.pid");
print $fh $$;
close $fh;
undef $fh;

my %serverconfig = (
		    'nick' => 'Tumblrbot',
		    'ircname' => "Tumblr IRC Perl Bot",
		    'username' => 'tumblrbot',
		    'server' => 'localhost',
		    'localaddr' => undef,
		    'port' => 7000,
		    'usessl' => 1,
		    'useipv6' => undef,
		   );

my %botconfig = (
		 'channels' => ["#laltromondo"],
		 'admins' => [ 'nobody!nobody@nowhere' ],
		 'fuckers' => [ 'fucker1',' fucker2'],
		 'nspassword' => 'nopass',
		);

my %tumblrconfig = (
		    'token' => undef,
		    'secret' => undef,
		    'tumblrlog' => undef
		   );

my %apikey = (
	      'c_key' => undef,
	      'c_secret' => undef
	     );


my $config_file = $ARGV[0];
my $debug = $ARGV[1];

show_help() unless $config_file;

### configuration checking 
my ($botconf, $serverconf, $tumblrconf) = LoadFile($config_file);
override_defaults(\%serverconfig, $serverconf);
override_defaults(\%botconfig, $botconf);
override_defaults(\%tumblrconfig, $tumblrconf);
my $cwd = getcwd();
my $apikey = LoadFile("$cwd/files/.apikey.conf");
override_defaults(\%apikey, $apikey);
my $c_key = $apikey{'c_key'};
my $c_secret = $apikey{'c_secret'};
my $tumblrlog = $tumblrconfig{'tumblrlog'};
my $token = $tumblrconfig{'token'};
my $secret = $tumblrconfig{'secret'};
my $posturl = 'http://api.tumblr.com/v2/blog/' . $tumblrlog . '/post';

warn_and_quit() unless ($token && $secret && $tumblrlog);

my %oauth_api_params =
    ('consumer_key' =>
        "$c_key",
     'consumer_secret' =>
        "$c_secret",
     'token' =>
        "$token",
     'token_secret' =>
        "$secret",
     'signature_method' =>
        'HMAC-SHA1',
     request_method => 'POST',
    );

print "Bot options: ", Dumper(\%botconfig),
  "Server options: ", Dumper(\%serverconfig),
  "Tumblr: ", Dumper(\%tumblrconfig);

my @channels = @{$botconfig{'channels'}};

# build the regexp of the admins
my @adminregexps = process_admin_list(@{$botconfig{'admins'}});

my @fuckers = @{$botconfig{'fuckers'}};
my $ircname = $serverconfig{'ircname'};


### starting POE stuff

my $irc = POE::Component::IRC::State->spawn(%serverconfig) 
  or die "WTF? $!\n";

my $dns = POE::Component::Client::DNS->spawn();

POE::Session->create(
		     package_states => [
					main => [ qw(_start
						     _default
						     irc_001 
						     irc_notice
						     irc_disconnected
						     irc_error
						     irc_socketerr
						     irc_ping
						     irc_botcmd_text
						     irc_botcmd_quote
						     irc_botcmd_photo
						     irc_botcmd_link
						     irc_botcmd_video
						     irc_botcmd_chat
						     irc_botcmd_audio
						     irc_botcmd_restart
						     irc_botcmd_version
						     greetings_and_die
						     ping_check
						     irc_public) ],
				       ],
		    );

$poe_kernel->run();

sub _start {
  my ($kernel) = $_[KERNEL];
  $irc->plugin_add('BotCommand', 
		   POE::Component::IRC::Plugin::BotCommand->new(
								Commands => {		    
									     restart => 'Restart Tumblr Bot',
									     text => 'Tumblr text post: (text <content> <[tag tag tag]> title)',
									     quote => 'Tumblr quote post: (quote <content> <[source]>)',
									     photo => 'Tumblr photo post: (photo <img url> <[tag tag tag]> title) - Supported formats: jpeg,jpg,png,bmp,gif,webp,svg.',
									     link => 'Tumblr link post: (link <url> <[title]> description)',
									     video => 'Tumblr video post: (video <embed> <[tag tag tag]> title) - "embed" is HTML embed code for the video or direct link to it.',
									     chat => 'Tumblr chat post: (chat <nick1> text -- <nick2> text -- <nick1> ..) - Each chat line takes an IRC nick prefixed by "<" and suffixed by ">" and then the actual message; "--" is used as separator between each chat line and we can have as many chat lines as they fill in an IRC message.',
									     audio => 'Tumblr audio post: (audio <external url> <[tag tag tag]> title) - "External url" is the URL of the site that hosts the audio file (not tumblr) and we only accept mp3.',
									     version => 'Shows our version and info'
									    },
								In_channels => 1,
								Auth_sub => \&check_if_fucker,
								Ignore_unauthorized => 1,
								In_private => 0,
								Addressed => 1,
								Ignore_unknown => 1
							       ));
  $irc->plugin_add( 'CTCP' => POE::Component::IRC::Plugin::CTCP->new(
								     version => "Tumblr IRC Perl Bot v.$VERSION",
								     userinfo => $ircname,
								    ));
  $irc->yield( register => 'all' );
  $irc->yield( connect => { } );
  $kernel->delay_set("ping_check", 60);  # first run after 60 seconds
  $lastpinged = time();
  return;
}

sub bot_says {
  my ($where, $what) = @_;
  return unless ($where and (defined $what));

  # Let's use HTML::Entities
  $what = decode_entities($what);
  
  if (length($what) < 400) {
    $irc->yield(privmsg => $where => $what);
  } else {
    my @output = ("");
    my @tokens = split (/\s+/, $what);
    $tokens[0] = ltrim($tokens[0]);
    while (@tokens) {
      my $string = shift(@tokens);
      my $len = length($string);
      my $oldstringleng = length($output[$#output]);
      if (($len + $oldstringleng) < 400) {
	$output[$#output] .= " $string";
      } else {
	push @output, $string;
	$output[0] = ltrim($output[0]);
      }
    }
    foreach my $reply (@output) {
      $irc->yield(privmsg => $where => $reply);
    }
  }
  return
}
  


sub irc_disconnected {
  print print_timestamp(), "Reconnecting in $reconnect_delay seconds\n";
  $irc->delay([ connect => { }], $reconnect_delay);
}

sub irc_error {
  print print_timestamp(), "Reconnecting in $reconnect_delay seconds\n";
  $irc->delay([ connect => { }], $reconnect_delay);
}

sub irc_socketerr {
  print print_timestamp(), "Reconnecting in $reconnect_delay seconds\n";
  $irc->delay([ connect => { }], $reconnect_delay);
}

sub irc_001 {
    my ($kernel, $sender) = @_[KERNEL, SENDER];

    # Since this is an irc_* event, we can get the component's object by
    # accessing the heap of the sender. Then we register and connect to the
    # specified server.
    my $irc = $sender->get_heap();

    print print_timestamp(), "Connected to ", $irc->server_name(), "\n";

    # we join our channels waiting a few secs
    foreach (@channels) {
      $irc->delay( [ join => $_ ], 10 ); 
    }

    return;
}

sub irc_notice {
  my ($who, $text) = @_[ARG0, ARG2];
  my $nick = parse_user($who);
  print "Notice from $who: $text", "\n";
  if ( ($nick eq 'NickServ' ) && ( $text =~ m/^This\snickname\sis\sregistered.+$/ || $text =~ m/^This\snick\sis\sowned\sby\ssomeone\selse\..+$/ ) ) {
    my $passwd = $botconfig{'nspassword'};
    $irc->yield( privmsg => "$nick", "IDENTIFY $passwd");
  }
}

sub irc_ping {
  print "Ping!\n";
  $lastpinged = time();
}


sub irc_public {
  my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];
  my $botnick = $irc->nick_name;
  
  # if it's a fucker, do nothing
  my ($auth, $spiterror) = check_if_fucker($sender, $who, $where, $what);
  return unless $auth;
}


sub _default {
  my ($event, $args) = @_[ARG0 .. $#_];
  my @output = ( "$event: " );
  
  for my $arg (@$args) {
    if ( ref $arg eq 'ARRAY' ) {
      push( @output, '[' . join(', ', @$arg ) . ']' );
    }
    else {
      push ( @output, "'$arg'" ) unless (! $arg);
    }
  }
  print print_timestamp(), join ' ', @output, "\n";
  return 0;
}


sub print_timestamp {
    my $time = localtime();
    return "[$time] "
}

sub process_admin_list {
  my @masks = @_;
  my @regexp;
  foreach my $mask (@masks) {
    # first, we check nick, username, host. The *!*@* form is required
    if ($mask =~ m/(.+)!(.+)@(.+)/) {
      $mask =~ s/(\W)/\\$1/g;	# escape everything which is not a \w
      $mask =~ s/\\\*/.*?/g;	# unescape the *
      push @regexp, qr/^$mask$/;
    } else {
      print "Invalid mask $mask, must be in *!*@* form"
    }
  }
  print Dumper(\@regexp);
  return @regexp;
}

sub check_if_admin {
  my $mask = shift;
  return 0 unless $mask;
  foreach my $regexp (@adminregexps) {
    if ($mask =~ m/$regexp/) {
      print "$mask authorized as admin\n";
      return 1
    }
  }
  return 0;
}

sub check_if_op {
  my ($chan, $nick) = @_;
  return 0 unless $nick;
  if (($irc->is_channel_operator($chan, $nick)) or 
      ($irc->nick_channel_modes($chan, $nick) =~ m/[aoq]/)) {
    print "$nick is an op on $chan\n";
    return 1;
  }
  else {
    return 0;
  }
}

sub check_if_fucker {
  my ($object, $nick, $place, $command, $args) = @_;
  foreach my $pattern (@fuckers) {
    if ($nick =~ m/\Q$pattern\E/i) {
      #print "$nick matches fucker pattern: $pattern\n";
      return 0, [];
    }
  }
  return 1;
}

sub is_where_a_channel {
  my $where = shift;
  if ($where =~ m/^#/) {
    return 1
  } else {
    return 0
  }
}

sub irc_botcmd_restart {                                                       
  my ($kernel, $who, $where, $arg) = @_[KERNEL, ARG0, ARG1, ARG2];             
  return unless check_if_admin($who);
  $poe_kernel->signal($poe_kernel, 'POCOIRC_SHUTDOWN', 'Goodbye, cruel world');
  $kernel->delay_set(greetings_and_die => 10);                                 
}

sub greetings_and_die {                         
  $ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH. 
  my @command = ('perl', $0, @ARGV);            
  exec @command or die "can't exec myself: $!"; 
}                                               

sub ping_check {
  my ($kernel, $sender) = @_[KERNEL, SENDER];
  my $currentime = time();
  if (($currentime - $lastpinged) > 200) {
    print print_timestamp(), "no ping in more then 200 secs, checking\n";
    $irc->yield( userhost => $serverconfig{nick} );
    $lastpinged = time();
  }
  $kernel->delay_set("ping_check", 60 );
}

sub irc_botcmd_text {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(.+)\s+\[(.+)\](.+)?$/) {
    
    my $title;
    my $string = $1;
    my $tags = trim($2);
    $title = trim($3) if ($3);
    $tags =~ s/\s+/,/g;

    print Dumper($string);
    print Dumper($tags);
    print Dumper($title);

    utf8::decode($string);
    utf8::decode($title);
    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'text',
			    'body' => "$string",
			    'tags' => "$tags",
			    'title' => "$title"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help text.");
    return;
  }
}

sub irc_botcmd_quote {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(.+)\s+\[(.+)\]\s*$/) {
    my $string = trim($1);
    my $source = trim($2);

    print Dumper($string);
    print Dumper($source);

    utf8::decode($string);
    utf8::decode($source);
    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'quote',
			    'quote' => "$string",
			    'source' => "$source"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help quote.");
    return;
  }
}

sub irc_botcmd_photo {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m,^(https?:\/\/.+\.(?i)(jpeg|jpg|png|bmp|gif|webp|svg))\s+\[(.+)\](.+)?$,) {

    my $title;
    my $source = trim($1);
    my $tags = trim($3);
    $title = trim($4) if ($4);
    $tags =~ s/\s+/,/g;

    print Dumper($source);
    print Dumper($tags);
    print Dumper($title);

    utf8::decode($source);
    utf8::decode($tags);
    utf8::decode($title);

    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'photo',
			    'source' => "$source",
			    'tags' => "$tags",
			    'caption' => "$title"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format or image: try help photo.");
    return;
  }
}

sub irc_botcmd_link {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(https?:\/\/.+)\s+\[(.+)\](.+)?$/) {
    
    my $description;
    my $link = $1;
    my $title = trim($2);
    $description = trim($3) if ($3);

    print Dumper($link);
    print Dumper($title);
    print Dumper($description);

    utf8::decode($link);
    utf8::decode($title);
    utf8::decode($description);

    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'link',
			    'url' => "$link",
			    'title' => "$title",
			    'description' => "$description"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help link.");
    return;
  }
}

sub irc_botcmd_video {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(.+)\s+\[(.+)\](.+)?$/) {

    my $title;
    my $embed = trim($1);
    my $tags = trim($2);
    $title = trim($3) if ($3);
    $tags =~ s/\s+/,/g;

    print Dumper($embed);
    print Dumper($tags);
    print Dumper($title);

    utf8::decode($embed);
    utf8::decode($tags);
    utf8::decode($title);

    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'video',
			    'embed' => "$embed",
			    'tags' => "$tags",
			    'caption' => "$title"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help video.");
    return;
  }
}

sub irc_botcmd_chat {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(\<[a-z_\-\[\]\\^{}|`][a-z0-9_\-\[\]\\^{}|`]{2,15}\>\s+.+\s*\--\s*\<[a-z_\-\[\]\\^{}|`][a-z0-9_\-\[\]\\^{}|`]{2,15}\>\s+.+)+\s*$/i) {

    print Dumper(\$1);
    my $string = $1;
    my @chat;
    my @blob = split(/--/, $string);
    print Dumper(\@blob);
    foreach my $message(@blob) {
      next if $message =~ m/^\s*$/;
      $message = trim($message);
      push @chat, $message;
    }
    my $chat = join("\n", @chat);
    print Dumper(\$chat);

    utf8::decode($chat);
    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'chat',
			    'conversation' => "$chat"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help chat.");
    return;
  }
}

sub irc_botcmd_audio {
  my ($who, $channel, $what) = @_[ARG0..$#_];
  my $nick = parse_user($who);
  return unless is_where_a_channel($channel);
  return unless (check_if_op($channel, $nick) || check_if_admin($who));
  if ($what =~ m/^(https?:\/\/.+\.mp3)\s+\[(.+)\](.+)?$/) {

    my $title;
    my $ext_url = trim($1);
    my $tags = trim($2);
    $title = trim($3) if ($3);
    $tags =~ s/\s+/,/g;

    print Dumper($ext_url);
    print Dumper($tags);
    print Dumper($title);

    utf8::decode($ext_url);
    utf8::decode($tags);
    utf8::decode($title);

    my $request =
      Net::OAuth->request("protected resource")->new
	  (request_url => $posturl,
	   %oauth_api_params,
	   timestamp => time(),
	   nonce => rand(1000000),
	   extra_params => {
			    'type' => 'audio',
			    'external_url' => "$ext_url",
			    'tags' => "$tags",
			    'caption' => "$title"
			   });
    
    bot_says($channel, post($request));
  } else {
    bot_says($channel, "Invalid format: try help audio.");
    return;
  }
}


sub post {
  my$request = shift;
  $request->sign;
  
  my $ua = LWP::UserAgent->new;
  my $response = $ua->request(POST $posturl, Content => $request->to_post_body);
  
  if ( $response->is_success ) {
    my $r = decode_json($response->content);
    if($r->{'meta'}{'status'} == 201) {
      my $item_id = $r->{'response'}{'id'};
      print("Added a Tumblr entry, http://$tumblrlog/post/$item_id \n");
      return "Content posted to tumblrlog.";
    } else {
      printf("Cannot create Tumblr entry: %s\n",
	     $r->{'meta'}{'msg'});
      return "We failed. Check logs";
    }            
  } else {
    printf("Cannot create Tumblr entry: %s\n",
	   $response->as_string);
    return "We failed. Check logs";
  }
}

#trim leading and trailing whitespaces
sub trim {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

#trim leading whitespaces
sub ltrim {
  my $string = shift;
  $string =~ s/^\s+//;
  return $string;
}

sub irc_botcmd_version {
  my $where = $_[ARG1];
  bot_says($where, "Tumblrbot v." . "$VERSION" . ", IRC Perl Bot.");
  return;
}


exit;
